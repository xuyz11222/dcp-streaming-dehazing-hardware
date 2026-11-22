#include <cstdio>
#include <cstdlib>
#include <vector>
using namespace std;

static int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static int quant8(int x, int n, int qround) {
    if (n == 8) return x;
    int m = (1 << n) - 1;
    return qround ? (x * m + 127) / 255 : (x * m) / 255;
}

static int to_y(int x, int cmax, int ymax) {
    return cmax ? (x * ymax + cmax/2) / cmax : 0;
}

struct Cfg {
    int nr, ng, nb, ny;
    int rmax, gmax, bmax, ymax;
    int qround;
};

static int min_y_at(const vector<unsigned char>& buf, int W, int H, int x, int y, const Cfg& c) {
    int x0 = x ? x - 1 : 0;
    int x1 = x;
    int x2 = x + 1 < W ? x + 1 : W - 1;
    int y0 = y ? y - 1 : 0;
    int y1 = y;
    int y2 = y + 1 < H ? y + 1 : H - 1;
    int best = c.ymax;
    for (int dy = 0; dy < 3; ++dy) {
        int yy = dy == 0 ? y0 : (dy == 1 ? y1 : y2);
        for (int dx = 0; dx < 3; ++dx) {
            int xx = dx == 0 ? x0 : (dx == 1 ? x1 : x2);
            int p = (yy * W + xx) * 3;
            int r = quant8(buf[p+0], c.nr, c.qround);
            int g = quant8(buf[p+1], c.ng, c.qround);
            int b = quant8(buf[p+2], c.nb, c.qround);
            int ry = to_y(r, c.rmax, c.ymax);
            int gy = to_y(g, c.gmax, c.ymax);
            int by = to_y(b, c.bmax, c.ymax);
            int m = ry < gy ? ry : gy;
            if (by < m) m = by;
            if (m < best) best = m;
        }
    }
    return best;
}

int main(int argc, char** argv) {
    if (argc < 10) {
        fprintf(stderr, "usage: %s W H NR NG NB NY QROUND in.raw out.raw\n", argv[0]);
        return 1;
    }
    int W = atoi(argv[1]), H = atoi(argv[2]);
    Cfg c;
    c.nr = atoi(argv[3]); c.ng = atoi(argv[4]); c.nb = atoi(argv[5]); c.ny = atoi(argv[6]);
    c.qround = atoi(argv[7]);
    c.rmax = (1 << c.nr) - 1;
    c.gmax = (1 << c.ng) - 1;
    c.bmax = (1 << c.nb) - 1;
    c.ymax = (1 << c.ny) - 1;
    int omega_q = (95 * (1 << c.ny) + 50) / 100;
    int t0 = (10 * c.ymax + 50) / 100;

    FILE* fi = fopen(argv[8], "rb");
    if (!fi) { fprintf(stderr, "cannot open %s\n", argv[8]); return 1; }
    int n = W * H;
    vector<unsigned char> buf((size_t)n * 6);
    if (fread(buf.data(), 1, buf.size(), fi) != buf.size()) {
        fprintf(stderr, "short read (need 2 frames)\n"); return 1;
    }
    fclose(fi);

    int A = 0;
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            int d = min_y_at(buf, W, H, x, y, c);
            if (d > A) A = d;
        }
    int a = A ? A : 1;

    FILE* fo = fopen(argv[9], "wb");
    if (!fo) { fprintf(stderr, "cannot open %s\n", argv[9]); return 1; }
    const unsigned char* f1 = &buf[(size_t)n * 3];
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            int p = (y * W + x) * 3;
            int r = quant8(f1[p+0], c.nr, c.qround);
            int g = quant8(f1[p+1], c.ng, c.qround);
            int b = quant8(f1[p+2], c.nb, c.qround);
            int jr = r, jg = g, jb = b;
            if (A) {
                int dark = min_y_at(buf, W, H, x, y, c);
                int ar = (a * c.rmax + c.ymax/2) / c.ymax;
                int ag = (a * c.gmax + c.ymax/2) / c.ymax;
                int ab = (a * c.bmax + c.ymax/2) / c.ymax;
                int norm = (dark * c.ymax + a/2) / a;
                if (norm > c.ymax) norm = c.ymax;
                int t = c.ymax - (omega_q * norm) / (1 << c.ny);
                if (t < t0) t = t0;
                jr = clampi(((r - ar) * c.ymax) / t + ar, 0, c.rmax);
                jg = clampi(((g - ag) * c.ymax) / t + ag, 0, c.gmax);
                jb = clampi(((b - ab) * c.ymax) / t + ab, 0, c.bmax);
            }
            int r8 = (jr * 255 + c.rmax/2) / c.rmax;
            int g8 = (jg * 255 + c.gmax/2) / c.gmax;
            int b8 = (jb * 255 + c.bmax/2) / c.bmax;
            unsigned char q[3] = {(unsigned char)r8, (unsigned char)g8, (unsigned char)b8};
            fwrite(q, 1, 3, fo);
        }
    }
    fclose(fo);
    printf("A=%d omega_q=%d t0=%d\n", A, omega_q, t0);
    return 0;
}
