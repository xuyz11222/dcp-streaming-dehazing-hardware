#include "Vdcp_stream_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
using namespace std;

double sc_time_stamp() { return 0.0; }

static vector<unsigned> read_raw(const char* path, int n) {
    vector<unsigned> v(n, 0);
    FILE* f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    for (int i = 0; i < n; ++i) {
        unsigned char q[3];
        if (fread(q, 1, 3, f) != 3) { fprintf(stderr, "short read %s\n", path); exit(1); }
        v[i] = ((unsigned)q[0] << 16) | ((unsigned)q[1] << 8) | q[2];
    }
    fclose(f);
    return v;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 6) {
        fprintf(stderr, "usage: %s W H in.raw ref.raw out.raw\n", argv[0]);
        return 1;
    }
    int W = atoi(argv[1]), H = atoi(argv[2]);
    int NP = W * H, TOT = (H + 1) * W, F = 2;
    vector<unsigned> img = read_raw(argv[3], NP * F);
    vector<unsigned> ref = read_raw(argv[4], NP);

    vector<unsigned> vin;
    vin.reserve((size_t)TOT * F);
    for (int fr = 0; fr < F; ++fr)
        for (int sy = 0; sy <= H; ++sy) {
            int yy = (sy == H) ? (H - 1) : sy;
            for (int sx = 0; sx < W; ++sx) vin.push_back(img[fr * NP + yy * W + sx]);
        }

    Vdcp_stream_top* d = new Vdcp_stream_top;
    d->clk = 0; d->rst_n = 0; d->start = 0; d->in_valid = 0; d->in_pixel = 0;
    for (int i = 0; i < 4; ++i) { d->clk = 0; d->eval(); d->clk = 1; d->eval(); }
    d->rst_n = 1; d->clk = 0; d->eval();
    d->start = 1; d->clk = 1; d->eval(); d->clk = 0; d->eval();
    d->start = 0;

    int idx = 0;
    long guard = 0;
    vector<unsigned> out;
    out.reserve(NP * F);
    const long LIMIT = 400L * F * (TOT + NP) + 10000;
    while ((int)out.size() < NP * F && guard < LIMIT) {
        d->clk = 0; d->eval();
        if (d->out_valid && (int)out.size() < NP * F) out.push_back(d->out_pixel & 0xFFFFFFu);
        bool ready = d->in_ready;
        if (ready && idx < (int)vin.size()) { d->in_valid = 1; d->in_pixel = vin[idx]; }
        else d->in_valid = 0;
        d->clk = 1; d->eval();
        d->clk = 0; d->eval();
        if (ready && idx < (int)vin.size()) ++idx;
        ++guard;
    }

    int bad = 0, shown = 0;
    for (int i = 0; i < NP && i < (int)out.size() - NP; ++i) {
        unsigned v = out[NP + i];
        if (v != ref[i]) {
            ++bad;
            if (shown < 12) {
                printf("  f1 px%d rtl=%06x ref=%06x\n", i, v, ref[i]);
                ++shown;
            }
        }
    }

    FILE* fo = fopen(argv[5], "wb");
    if (!fo) { fprintf(stderr, "cannot open %s\n", argv[5]); return 1; }
    for (int i = 0; i < NP && i + NP < (int)out.size(); ++i) {
        unsigned v = out[NP + i];
        unsigned char q[3] = {(unsigned char)(v >> 16), (unsigned char)(v >> 8), (unsigned char)v};
        fwrite(q, 1, 3, fo);
    }
    fclose(fo);

    printf("dcp_video_tb: W=%d H=%d in=%d out=%d A=%d mismatches=%d guard=%ld\n",
           W, H, idx, (int)out.size(), (int)d->A_dbg, bad, guard);
    printf("%s\n", (bad == 0 && (int)out.size() >= NP * F) ? "PASS" : "FAIL");
    d->final(); delete d;
    return (bad == 0 && (int)out.size() >= NP * F) ? 0 : 2;
}
