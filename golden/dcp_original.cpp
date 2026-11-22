#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>
using namespace std;

static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
static int idx(int x, int y, int w) { return y * w + x; }

static vector<double> box_mean(const vector<double>& src, int w, int h, int r) {
    int W = w + 1;
    vector<double> integ((size_t)W * (h + 1), 0.0);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x)
            integ[(y+1)*W + (x+1)] = src[y*w+x]
                + integ[y*W + (x+1)] + integ[(y+1)*W + x] - integ[y*W + x];
    vector<double> out((size_t)w * h);
    for (int y = 0; y < h; ++y) {
        int y0 = max(0, y - r), y1 = min(h - 1, y + r);
        for (int x = 0; x < w; ++x) {
            int x0 = max(0, x - r), x1 = min(w - 1, x + r);
            double s = integ[(y1+1)*W + (x1+1)] - integ[y0*W + (x1+1)]
                     - integ[(y1+1)*W + x0] + integ[y0*W + x0];
            out[y*w+x] = s / ((x1-x0+1.0) * (y1-y0+1.0));
        }
    }
    return out;
}

static vector<double> guided_filter(const vector<double>& guide,
                                    const vector<double>& src,
                                    int w, int h, int r, double eps) {
    vector<double> meanI = box_mean(guide, w, h, r);
    vector<double> meanP = box_mean(src, w, h, r);
    vector<double> II((size_t)w*h), IP((size_t)w*h);
    for (int i = 0; i < w*h; ++i) { II[i] = guide[i]*guide[i]; IP[i] = guide[i]*src[i]; }
    vector<double> meanII = box_mean(II, w, h, r);
    vector<double> meanIP = box_mean(IP, w, h, r);
    vector<double> a((size_t)w*h), b((size_t)w*h);
    for (int i = 0; i < w*h; ++i) {
        double varI = meanII[i] - meanI[i]*meanI[i];
        double covIP = meanIP[i] - meanI[i]*meanP[i];
        a[i] = covIP / (varI + eps);
        b[i] = meanP[i] - a[i]*meanI[i];
    }
    vector<double> ma = box_mean(a, w, h, r);
    vector<double> mb = box_mean(b, w, h, r);
    vector<double> q((size_t)w*h);
    for (int i = 0; i < w*h; ++i) q[i] = ma[i]*guide[i] + mb[i];
    return q;
}

int main(int argc, char** argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s W H in.raw out.raw\n", argv[0]);
        return 1;
    }
    int W = atoi(argv[1]), H = atoi(argv[2]);
    int n = W * H;
    FILE* fi = fopen(argv[3], "rb");
    if (!fi) { fprintf(stderr, "cannot open %s\n", argv[3]); return 1; }
    vector<unsigned char> buf((size_t)n * 3);
    if (fread(buf.data(), 1, buf.size(), fi) != buf.size()) {
        fprintf(stderr, "short read\n"); return 1;
    }
    fclose(fi);

    const int radius = 7;
    vector<double> dark((size_t)n, 255.0);
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            double m = 255.0;
            for (int dy = -radius; dy <= radius; ++dy) {
                int yy = clampi(y + dy, 0, H - 1);
                for (int dx = -radius; dx <= radius; ++dx) {
                    int xx = clampi(x + dx, 0, W - 1);
                    int p = idx(xx, yy, W) * 3;
                    double v = min(buf[p], min(buf[p+1], buf[p+2]));
                    if (v < m) m = v;
                }
            }
            dark[idx(x,y,W)] = m;
        }

    int cnt = max(1, (int)(0.001 * n));
    vector<int> order((size_t)n);
    for (int i = 0; i < n; ++i) order[i] = i;
    sort(order.begin(), order.end(), [&](int i, int j) { return dark[i] > dark[j]; });
    int best = order[0];
    double bestSum = 0;
    for (int k = 0; k < cnt; ++k) {
        int p = order[k] * 3;
        double s = buf[p] + buf[p+1] + buf[p+2];
        if (s > bestSum) { bestSum = s; best = order[k]; }
    }
    int bp = best * 3;
    double A[3] = {buf[bp] / 255.0, buf[bp+1] / 255.0, buf[bp+2] / 255.0};
    if (A[0] <= 0) A[0] = 1e-3;
    if (A[1] <= 0) A[1] = 1e-3;
    if (A[2] <= 0) A[2] = 1e-3;

    vector<double> t((size_t)n, 1.0), guide((size_t)n, 0.0);
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            double m = 255.0;
            for (int dy = -radius; dy <= radius; ++dy) {
                int yy = clampi(y + dy, 0, H - 1);
                for (int dx = -radius; dx <= radius; ++dx) {
                    int xx = clampi(x + dx, 0, W - 1);
                    int p = idx(xx, yy, W) * 3;
                    double nr = buf[p+0] / 255.0 / A[0];
                    double ng = buf[p+1] / 255.0 / A[1];
                    double nb = buf[p+2] / 255.0 / A[2];
                    double v = min(nr, min(ng, nb));
                    if (v < m) m = v;
                }
            }
            int i = idx(x,y,W);
            t[i] = 1.0 - 0.95 * m;
            guide[i] = (0.299 * buf[i*3] + 0.587 * buf[i*3+1] + 0.114 * buf[i*3+2]) / 255.0;
        }

    vector<double> tr = guided_filter(guide, t, W, H, 40, 1e-3);
    FILE* fo = fopen(argv[4], "wb");
    if (!fo) { fprintf(stderr, "cannot open %s\n", argv[4]); return 1; }
    for (int i = 0; i < n; ++i) {
        double tt = max(0.1, tr[i]);
        int r = clampi((int)(((buf[i*3+0]/255.0 - A[0]) / tt + A[0]) * 255.0 + 0.5), 0, 255);
        int g = clampi((int)(((buf[i*3+1]/255.0 - A[1]) / tt + A[1]) * 255.0 + 0.5), 0, 255);
        int b = clampi((int)(((buf[i*3+2]/255.0 - A[2]) / tt + A[2]) * 255.0 + 0.5), 0, 255);
        unsigned char q[3] = {(unsigned char)r, (unsigned char)g, (unsigned char)b};
        fwrite(q, 1, 3, fo);
    }
    fclose(fo);
    printf("A=(%.1f,%.1f,%.1f)\n", A[0]*255, A[1]*255, A[2]*255);
    return 0;
}
