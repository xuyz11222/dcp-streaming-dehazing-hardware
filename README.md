# DCP Streaming Dehazing Hardware

Parameterized dark-channel-prior (DCP) streaming dehazing hardware with joint precision–area optimization.

This repository is the canonical reproduction package (`project2`). The older `project1` tree is a working/scratch directory and is not part of this release.

## What is included

- `rtl/` — streaming DCP RTL: 3×3 dark channel, per-frame automatic atmospheric light, transmission and scene recovery.
- `golden/` — C++ parameterized fixed-point golden model and original DCP reference.
- `tb/` — Verilator testbench for two-frame bit-exact comparison.
- `tools/dcp_sweep.py` — quality sweep (`PSNR`, `SSIM`, `CIEDE2000`, `Q`).
- `tools/dcp_opt.py` — discrete steepest-ascent search over `(N_R, N_G, N_B, N_Y)`.
- `tools/raw_to_png.py` — raw RGB888 to PNG.
- `data/` — input, golden and reference raw images used by the paper.
- `docs/evidence/` — raw tool logs (`hill_A.log`, `hill_B.log`, `quality_points.log`, `real_image_metrics.log`, area logs, SHA256 manifest).
- `docs/figures/` — figures used in the report.

## Hardware model

Input/output are RGB888. Internally the datapath is parameterized by `N_R, N_G, N_B, N_Y`:

- RGB formats: 888, 787, 666, 565, 444, …
- `N_Y` = 5..8 bits
- 3×3 dark channel, per-frame automatic atmospheric light, 1 pixel/cycle steady state
- Line buffer is a blackbox in area estimation; only datapath logic is counted.

## Results (384×384, eslim ABC, line buffer as blackbox)

Two parallel steepest-ascent experiments share the same RTL, golden and area flow.

| Setting | Threshold | Area weight | Optimum | Q | LUT6 | Area reduction | score |
|---|---:|---:|---|---:|---:|---:|---:|
| A | Q>80 | 200 | 888/5 | 80.43 | 379 | 26.55% | 133.53 |
| B | Q>90 | 120 | 888/7 | 97.62 | 467 | 9.50% | 109.01 |

Baseline 888/8: Q = 100.00, LUT6 = 516. Setting C (Q>80, weight 300) selects 888/5 with score 160.08, computed from A's verified Q/LUT6.

Raw evidence: `docs/evidence/hill_A.log`, `docs/evidence/hill_B.log`, `docs/evidence/quality_points.log`, `docs/evidence/real_image_metrics.log`.

## Dependencies

- Verilator (with `verilator_bin`)
- g++ (C++20)
- Python 3 with `numpy` and `scikit-image`
- Yosys
- ABC (Berkeley ABC)

Paths can be overridden by environment variables or script arguments:

```text
VERILATOR_HOME / VERILATOR
GPP
PYTHON
YOSYS
ABC / ABC_PATH
```

## Reproduce

Quick mode (verified; skips ABC optimization):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_repro.ps1 -SkipOptimize
```

Full mode (also runs steepest ascent):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_repro.ps1
```

Manual experiments:

```powershell
python tools\dcp_opt.py --start 8,8,8,8 --workers 8 --qmin 80 --area-weight 200
python tools\dcp_opt.py --start 8,8,8,8 --workers 8 --qmin 90 --area-weight 120
python tools\dcp_opt.py --start 8,8,8,8 --workers 8 --qmin 80 --area-weight 300
```

Expected stops:

```text
STOP at (8, 8, 8, 5) Q=80.43 lut=379 score=133.53
STOP at (8, 8, 8, 7) Q=97.62 lut=467 score=109.01
```

## Notes

- `Q` measures fidelity relative to the 888 golden, not absolute dehazing quality against a clean image.
- The current RTL does not include guided filtering; low `N_Y` quantizes the transmission map and can produce banding/halos.
- All quality numbers in the report are regenerated with the tools in this repository. `project1` outputs are not used as evidence.

## License

MIT. See `LICENSE`.
