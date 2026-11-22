#!/usr/bin/env python3
"""Steepest-ascent for DCP precision knobs.

score = Q + 200 * (LUT_888 - LUT) / LUT_888,  subject to Q > 80.
Neighbors change exactly one of NR, NG, NB, NY by +/-1.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import dcp_sweep

W = 384
H = 384
IN_RAW = ROOT / "data" / "real_dcp" / "in.raw"
REF_RAW = ROOT / "data" / "dcp_ref" / "golden_video.raw"

YOSYS = Path(os.environ.get("YOSYS", r"D:\Anaconda3\Scripts\yowasp-yosys.exe"))
ABC = Path(os.environ.get("ABC", r"F:\ICT\eslim\abc.exe"))
ABC_PATH = os.environ.get("ABC_PATH", str(ABC.parent))
AREA_DIR = ROOT / "build" / "dcp_hill_area"
RTL = ["dcp_stream_top.v", "rgb_front.v", "dcp_auto_a.v", "dcp_calc.v",
       "win3x3_min.v", "fifo_line_bb.v"]


def run(cmd, cwd, env_extra=None, timeout=300):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    p = subprocess.run(cmd, cwd=str(cwd), env=env, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True, timeout=timeout)
    return p.returncode, p.stdout


def area(c):
    nr, ng, nb, ny = c
    tag = f"r{nr}g{ng}b{nb}y{ny}"
    d = AREA_DIR / tag
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    for f in RTL:
        shutil.copy(ROOT / "rtl" / f, d / f)
    wrap = f"""module dcp_synth (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        in_valid,
    input  wire [23:0] in_pixel,
    output wire        in_ready,
    output wire        out_valid,
    output wire [23:0] out_pixel,
    output wire        done,
    output wire [{ny-1}:0] A_dbg
);
    dcp_stream_top #(.W({W}), .H({H}), .NR({nr}), .NG({ng}),
                     .NB({nb}), .NY({ny})) u (
        .clk(clk), .rst_n(rst_n), .start(start), .in_valid(in_valid),
        .in_pixel(in_pixel), .in_ready(in_ready), .out_valid(out_valid),
        .out_pixel(out_pixel), .done(done), .A_dbg(A_dbg)
    );
endmodule
"""
    (d / "synth_wrap.v").write_text(wrap, encoding="ascii")
    ys = """read_verilog dcp_stream_top.v
read_verilog rgb_front.v
read_verilog dcp_auto_a.v
read_verilog dcp_calc.v
read_verilog win3x3_min.v
read_verilog fifo_line_bb.v
read_verilog synth_wrap.v
hierarchy -top dcp_synth
proc; opt
memory_map; opt
async2sync; opt
techmap
opt
dfflegalize -cell $_DFF_P_ x -cell $_DFF_N_ x
opt -nodffe -nosdff
flatten
write_blif -blackbox -noalias design.blif
"""
    (d / "to_blif.ys").write_text(ys, encoding="ascii")
    rc, out = run([str(YOSYS), "-s", "to_blif.ys"], d)
    if rc:
        raise RuntimeError(f"yosys failed {tag}:\n{out[-1000:]}")
    abc_cmd = ("read_blif -n design.blif; strash; zero; balance; rewrite; "
               "rewrite -z; balance; if -K 6 -a; print_stats")
    env = {"Path": ABC_PATH + ";" + os.environ.get("Path", "")}
    rc, out = run([str(ABC), "-c", abc_cmd], d, env_extra=env)
    if rc:
        raise RuntimeError(f"abc failed {tag}:\n{out[-1000:]}")
    mlat = re.search(r"lat\s*=\s*(\d+)", out)
    mnd = re.search(r"\bnd\s*=\s*(\d+)", out)
    if not mlat or not mnd:
        raise RuntimeError(f"cannot parse ABC {tag}")
    return int(mlat.group(1)), int(mnd.group(1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start", default="8,8,8,8")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--qmin", type=float, default=80.0)
    ap.add_argument("--area-weight", type=float, default=200.0)
    ap.add_argument("--min-rgb", type=int, default=4)
    ap.add_argument("--max-rgb", type=int, default=8)
    ap.add_argument("--min-y", type=int, default=5)
    ap.add_argument("--max-y", type=int, default=8)
    args = ap.parse_args()
    qcache = {}
    acache = {}
    qlock = threading.Lock()
    alock = threading.Lock()

    def qual(c):
        with qlock:
            if c in qcache:
                return qcache[c]
        r = dcp_sweep.one(c, W, H, IN_RAW, REF_RAW)
        if r.get("error"):
            raise RuntimeError(r["error"])
        with qlock:
            qcache[c] = r
        return r

    def ar(c):
        with alock:
            if c in acache:
                return acache[c]
        v = area(c)
        with alock:
            acache[c] = v
        return v

    start = tuple(map(int, args.start.split(",")))
    ref_regs, ref_lut = ar((8, 8, 8, 8))
    print(f"888: regs={ref_regs} lut6={ref_lut}", flush=True)

    def evaluate(c):
        q = qual(c)
        if q["q"] <= args.qmin:
            return {"c": c, "q": q["q"], "lut": None, "score": -1e9,
                    "psnr": q["psnr"], "ssim": q["ssim"], "de": q["de"]}
        regs, lut = ar(c)
        saving = (ref_lut - lut) / ref_lut
        score = q["q"] + args.area_weight * saving
        return {"c": c, "q": q["q"], "lut": lut, "regs": regs,
                "score": score, "psnr": q["psnr"], "ssim": q["ssim"], "de": q["de"],
                "saving": saving}

    cur = evaluate(start)
    print(f"START {cur['c']} Q={cur['q']:.2f} lut={cur['lut']} "
          f"score={cur['score']:.2f}", flush=True)
    step = 0
    while True:
        step += 1
        cand = []
        for i in range(4):
            for d in (-1, 1):
                c = list(cur["c"])
                c[i] += d
                c = tuple(c)
                if not (args.min_rgb <= c[0] <= args.max_rgb and
                        args.min_rgb <= c[1] <= args.max_rgb and
                        args.min_rgb <= c[2] <= args.max_rgb and
                        args.min_y <= c[3] <= args.max_y):
                    continue
                if c not in cand:
                    cand.append(c)
        nbrs = []
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            futs = {ex.submit(evaluate, c): c for c in cand}
            for fut in as_completed(futs):
                nbrs.append(fut.result())
        nbrs.sort(key=lambda r: -r["score"])
        print(f"\nSTEP {step} from {cur['c']}", flush=True)
        for r in nbrs:
            print(f"  {r['c']} Q={r['q']:.2f} lut={r['lut']} "
                  f"score={r['score']:.2f}", flush=True)
        best = nbrs[0] if nbrs else None
        if not best or best["score"] <= cur["score"] + 1e-9:
            print(f"\nSTOP at {cur['c']} Q={cur['q']:.2f} "
                  f"lut={cur['lut']} score={cur['score']:.2f}", flush=True)
            break
        cur = best
        print(f"  ACCEPT {cur['c']} score={cur['score']:.2f}", flush=True)


if __name__ == "__main__":
    main()
