param(
    [switch]$SkipOptimize,
    [string]$VerilatorHome = $env:VERILATOR_HOME,
    [string]$Gpp = $env:GPP,
    [string]$Python = $env:PYTHON,
    [string]$Yosys = $env:YOSYS,
    [string]$Abc = $env:ABC
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location $root

if (-not $VerilatorHome) { $VerilatorHome = 'D:\Anaconda3\envs\verilator' }
if (-not $Gpp) { $Gpp = 'C:\Program Files\CodeBlocks\MinGW\bin\g++.exe' }
if (-not $Python) { $Python = 'D:\Anaconda3\python.exe' }
if (-not $Yosys) { $Yosys = 'D:\Anaconda3\Scripts\yowasp-yosys.exe' }
if (-not $Abc) { $Abc = 'F:\ICT\eslim\abc.exe' }

$VR = Join-Path $VerilatorHome 'Library'
$VERILATOR = Join-Path $VR 'bin\verilator_bin.exe'

if (-not (Test-Path -LiteralPath $VERILATOR)) { throw "Verilator not found: $VERILATOR" }
if (-not (Test-Path -LiteralPath $Gpp)) { throw "g++ not found: $Gpp" }
if (-not (Test-Path -LiteralPath $Python)) { throw "Python not found: $Python" }
if (-not $SkipOptimize) {
    if (-not (Test-Path -LiteralPath $Yosys)) { throw "Yosys not found: $Yosys" }
    if (-not (Test-Path -LiteralPath $Abc)) { throw "ABC not found: $Abc" }
}

$env:VERILATOR_HOME = $VerilatorHome
$env:VERILATOR_ROOT = "$VR\"
$env:GPP = $Gpp
$env:PYTHON = $Python
$env:YOSYS = $Yosys
$env:ABC = $Abc
$env:ABC_PATH = (Split-Path -Parent $Abc)
$env:Path = "$VerilatorHome;$VR\mingw-w64\bin;$VR\bin;$VerilatorHome\Scripts;$VerilatorHome\bin;$env:Path"

New-Item -ItemType Directory -Force -Path build, data\dcp_ref | Out-Null

# ---------------------------------------------------------------- 1
Write-Host '[1/4] original DCP: C++ output image'
& $Gpp -O2 -std=c++17 -static -static-libgcc -static-libstdc++ `
    -o build\dcp_original.exe golden\dcp_original.cpp
if ($LASTEXITCODE -ne 0) { throw 'original DCP build failed' }
& build\dcp_original.exe 384 384 data\real_dcp\in.raw data\dcp_ref\original_dcp_cpp.raw
if ($LASTEXITCODE -ne 0) { throw 'original DCP run failed' }
& $Python tools\raw_to_png.py 384 384 data\dcp_ref\original_dcp_cpp.raw data\dcp_ref\original_dcp_cpp.png
if ($LASTEXITCODE -ne 0) { throw 'original DCP PNG failed' }

# ---------------------------------------------------------------- 2
Write-Host '[2/4] 888/8: C++ output image'
& $Gpp -O2 -std=c++17 -static -static-libgcc -static-libstdc++ `
    -o build\dcp_golden.exe golden\dcp_video_golden_param.cpp
if ($LASTEXITCODE -ne 0) { throw 'golden build failed' }
& build\dcp_golden.exe 384 384 8 8 8 8 1 data\real_dcp\in.raw data\dcp_ref\dcp_888_8_cpp.raw
if ($LASTEXITCODE -ne 0) { throw '888/8 C++ failed' }
& $Python tools\raw_to_png.py 384 384 data\dcp_ref\dcp_888_8_cpp.raw data\dcp_ref\dcp_888_8_cpp.png
if ($LASTEXITCODE -ne 0) { throw '888/8 PNG failed' }

# ---------------------------------------------------------------- 3
Write-Host '[3/4] steepest ascent: find final config'
$finalCfg = @(8, 8, 8, 5)
if (-not $SkipOptimize) {
    $optLines = & $Python tools\dcp_opt.py --start 8,8,8,8 --workers 8 --qmin 80 --area-weight 200 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'optimization failed' }
    $optLines | ForEach-Object { Write-Host $_ }
    $optText = $optLines -join "`n"
    $m = [regex]::Match($optText, 'STOP at \((\d+), (\d+), (\d+), (\d+)\) Q=([0-9.]+) lut=(\d+) score=([0-9.]+)')
    if (-not $m.Success) { throw 'cannot parse optimizer result' }
    $finalCfg = @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value,
                  [int]$m.Groups[3].Value, [int]$m.Groups[4].Value)
    $finalQ = [double]$m.Groups[5].Value
    $finalLut = [int]$m.Groups[6].Value
    $finalScore = [double]$m.Groups[7].Value
    Write-Host "optimizer selected: $($finalCfg -join ',') Q=$finalQ LUT6=$finalLut score=$finalScore"
    if (($finalCfg -join ',') -ne '8,8,8,5') { throw "optimizer selected $($finalCfg -join ',') but report expects 8,8,8,5" }
    if ([math]::Abs($finalQ - 80.43) -gt 0.01) { throw "unexpected Q: $finalQ" }
    if ($finalLut -ne 379) { throw "unexpected LUT6: $finalLut" }
} else {
    Write-Host '  skipped by -SkipOptimize; using expected 888/5'
}

# ---------------------------------------------------------------- 4
$fnr = [int]$finalCfg[0]; $fng = [int]$finalCfg[1]
$fnb = [int]$finalCfg[2]; $fny = [int]$finalCfg[3]
Write-Host "[4/4] final $($finalCfg -join '/') : C++ output image and RTL check"
& build\dcp_golden.exe 384 384 $fnr $fng $fnb $fny 1 `
    data\real_dcp\in.raw data\dcp_ref\final_888_5_cpp.raw
if ($LASTEXITCODE -ne 0) { throw 'final C++ failed' }
& $Python tools\raw_to_png.py 384 384 data\dcp_ref\final_888_5_cpp.raw data\dcp_ref\final_888_5_cpp.png
if ($LASTEXITCODE -ne 0) { throw 'final PNG failed' }

function Build-Sim([string]$name, [int]$nr, [int]$ng, [int]$nb, [int]$ny) {
    $dir = Join-Path 'build' $name
    $obj = Join-Path $dir 'obj'
    if (Test-Path -LiteralPath $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force -Path $obj | Out-Null
    & $VERILATOR --cc --top-module dcp_stream_top `
        -GW=384 -GH=384 "-GNR=$nr" "-GNG=$ng" "-GNB=$nb" "-GNY=$ny" `
        --Mdir $obj -Wno-fatal -Wno-WIDTH `
        rtl\dcp_stream_top.v rtl\rgb_front.v rtl\dcp_auto_a.v `
        rtl\dcp_calc.v rtl\win3x3_min.v rtl\fifo_line.v
    if ($LASTEXITCODE -ne 0) { throw "verilator failed: $name" }
    $objs = Get-ChildItem -LiteralPath $obj -Filter *.cpp | ForEach-Object { $_.FullName }
    $srcs = @('tb\dcp_video_tb.cpp') + $objs + @(
        "$VR\include\verilated.cpp",
        "$VR\include\verilated_dpi.cpp",
        "$VR\include\verilated_threads.cpp",
        "$VR\include\verilated_timing.cpp"
    )
    & $Gpp -O2 -std=c++20 -w -static -static-libgcc -static-libstdc++ `
        "-I$VR\include" "-I$VR\include\vltstd" "-I$obj" @srcs -o (Join-Path $dir 'sim.exe')
    if ($LASTEXITCODE -ne 0) { throw "g++ failed: $name" }
}

Build-Sim 'dcp_888_5' $fnr $fng $fnb $fny
& build\dcp_888_5\sim.exe 384 384 data\real_dcp\in.raw data\dcp_ref\final_888_5_cpp.raw data\dcp_ref\rtl_888_5.raw
if ($LASTEXITCODE -ne 0) { throw 'final RTL failed or mismatched' }

$hCpp = (Get-FileHash -Algorithm SHA256 data\dcp_ref\final_888_5_cpp.raw).Hash
$hRtl = (Get-FileHash -Algorithm SHA256 data\dcp_ref\rtl_888_5.raw).Hash
$h888 = (Get-FileHash -Algorithm SHA256 data\dcp_ref\dcp_888_8_cpp.raw).Hash
$hRef = (Get-FileHash -Algorithm SHA256 data\dcp_ref\golden_video.raw).Hash
Write-Host "C++ 888/5 SHA256 = $hCpp"
Write-Host "RTL 888/5 SHA256 = $hRtl"
Write-Host "C++ 888/8 SHA256 = $h888"
Write-Host "included 888 SHA256 = $hRef"
if ($hCpp -ne $hRtl) { throw 'C++ final != RTL final' }
if ($h888 -ne $hRef) { throw 'C++ 888/8 != included 888 golden' }

Write-Host ''
Write-Host 'outputs:'
Write-Host '  data/dcp_ref/original_dcp_cpp.png   original DCP C++'
Write-Host '  data/dcp_ref/dcp_888_8_cpp.png       888/8 C++'
Write-Host '  data/dcp_ref/final_888_5_cpp.png     final 888/5 C++'
Write-Host 'PASS: original/888/final outputs generated; bit-exact checks passed.'
