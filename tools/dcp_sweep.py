#!/usr/bin/env python3
"""Quality sweep for the parameterized DCP RTL.

Each point (NR,NG,NB,NY) is simulated on two identical frames; the first
frame learns A and the second frame is compared with the fixed 888 golden.
"""
import argparse
import csv
import itertools
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np
from skimage import color
from skimage.metrics import structural_similarity

ROOT = Path(__file__).resolve().parents[1]
VENV = Path(os.environ.get("VERILATOR_HOME", r"D:\Anaconda3\envs\verilator"))
VR = VENV / "Library"
VERILATOR = Path(os.environ.get("VERILATOR", str(VR / "bin" / "verilator_bin.exe")))
GPP = Path(os.environ.get("GPP", r"C:\Program Files\CodeBlocks\MinGW\bin\g++.exe"))
PYTHON = Path(os.environ.get("PYTHON", r"D:\Anaconda3\python.exe"))

RTL = ["rtl/dcp_stream_top.v", "rtl/rgb_front.v", "rtl/dcp_auto_a.v",
       "rtl/dcp_calc.v", "rtl/win3x3_min.v", "rtl/fifo_line.v"]
TB = ROOT / "tb" / "dcp_sweep_tb.cpp"
CSV = ROOT / "data" / "dcp_opt" / "quality.csv"
BUILD = ROOT / "build" / "dcp_sweep"


def run(cmd, cwd=ROOT, timeout=180):
    env = os.environ.copy()
    env["VERILATOR_ROOT"] = str(VR)
    env["Path"] = (f"{VENV};{GPP.parent};{VR/'mingw-w64'/'bin'};"
                   f"{VR/'bin'};{VENV/'Scripts'};" + env.get("Path", ""))
    p = subprocess.run(cmd, cwd=str(cwd), env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True, timeout=timeout)
    return p.returncode, p.stdout


def one(c, w, h, in_raw, ref_raw):
    nr, ng, nb, ny = c
    tag = f"r{nr}g{ng}b{nb}y{ny}"
    d = Path(tempfile.mkdtemp(prefix="dcp_" + tag + "_"))
    obj = d / "obj"
    obj.mkdir(parents=True, exist_ok=True)
    rc, out = run([str(VERILATOR), "--cc", "--top-module", "dcp_stream_top",
                   f"-GW={w}", f"-GH={h}", f"-GNR={nr}", f"-GNG={ng}",
                   f"-GNB={nb}", f"-GNY={ny}", "--Mdir", str(obj),
                   "-Wno-fatal", "-Wno-WIDTH"] + RTL)
    if rc:
        return {"nr": nr, "ng": ng, "nb": nb, "ny": ny, "error": out[-200:]}
    objs = [str(p) for p in obj.glob("*.cpp")]
    srcs = [str(TB)] + objs + [
        str(VR / "include" / "verilated.cpp"),
        str(VR / "include" / "verilated_dpi.cpp"),
        str(VR / "include" / "verilated_threads.cpp"),
        str(VR / "include" / "verilated_timing.cpp"),
    ]
    sim = d / "sim.exe"
    rc, out = run([str(GPP), "-O2", "-std=c++20", "-w", "-static",
                   "-static-libgcc", "-static-libstdc++",
                   f"-I{VR/'include'}", f"-I{VR/'include'/'vltstd'}",
                   f"-I{obj}"] + srcs + ["-o", str(sim)])
    if rc:
        return {"nr": nr, "ng": ng, "nb": nb, "ny": ny, "error": out[-200:]}
    out_raw = d / "rtl.raw"
    rc, out = run([str(sim), str(w), str(h), str(in_raw), str(out_raw)])
    if rc:
        return {"nr": nr, "ng": ng, "nb": nb, "ny": ny, "error": out[-200:]}
    am = re.search(r"A=(\d+)", out)
    aval = int(am.group(1)) if am else 0
    a = np.fromfile(ref_raw, np.uint8).reshape(h, w, 3).astype(np.float64)
    b = np.fromfile(out_raw, np.uint8).reshape(h, w, 3).astype(np.float64)
    mse = float(np.mean((a - b) ** 2))
    psnr = 99.0 if mse == 0 else 10.0 * math.log10(255.0 ** 2 / mse)
    ssim = float(structural_similarity(a, b, channel_axis=2, data_range=255))
    de = float(np.mean(color.deltaE_ciede2000(color.rgb2lab(a / 255.0),
                                              color.rgb2lab(b / 255.0))))
    q = 100.0 * (0.4 * min(1.0, psnr / 40.0) + 0.4 * ssim +
                 0.2 * max(0.0, 1.0 - de / 10.0))
    shutil.rmtree(d, ignore_errors=True)
    return {"nr": nr, "ng": ng, "nb": nb, "ny": ny, "A": aval,
            "psnr": psnr, "ssim": ssim, "de": de, "q": q, "error": ""}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--w", type=int, default=384)
    ap.add_argument("--h", type=int, default=384)
    ap.add_argument("--min-bits", type=int, default=4)
    ap.add_argument("--max-bits", type=int, default=8)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--in", default="data/real_dcp/in.raw")
    ap.add_argument("--ref", default="data/dcp_ref/golden_video.raw")
    args = ap.parse_args()
    CSV.parent.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    in_raw = ROOT / getattr(args, "in")
    ref_raw = ROOT / args.ref
    vals = range(args.min_bits, args.max_bits + 1)
    cfgs = list(itertools.product(vals, repeat=4))
    rows = []
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(one, c, args.w, args.h, in_raw, ref_raw): c for c in cfgs}
        for i, fut in enumerate(as_completed(futs), 1):
            r = fut.result()
            rows.append(r)
            if r.get("error"):
                print(f"FAIL {r['nr']}{r['ng']}{r['nb']}/{r['ny']}: {r['error']}", flush=True)
            else:
                print(f"[{i}/{len(cfgs)}] {r['nr']}{r['ng']}{r['nb']}/{r['ny']} "
                      f"Q={r['q']:.2f} PSNR={r['psnr']:.2f} SSIM={r['ssim']:.3f} dE={r['de']:.2f}",
                      flush=True)
    fields = ["nr", "ng", "nb", "ny", "A", "psnr", "ssim", "de", "q", "error"]
    with open(CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in sorted(rows, key=lambda r: -r.get("q", -1)):
            w.writerow(r)
    print(f"wrote {CSV}")


if __name__ == "__main__":
    main()
