# Trilobite cephalon outlines (Trimerocephalus lelievrei, Crônier et al. 1998; Momocs `trilo`):
# elliptic Fourier descriptors, the app's "as oriented" normalisation, PCA by growth stage, and a few
# checks of how well shape separates the stages. Same method as the app, at full precision.
# Run from this folder: python3 analyse.py  (needs numpy and matplotlib; writes trilobites.png)
import json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

N, M = 20, 1024                      # harmonics; points the outline is resampled to
with open("Trilobites.epicycles.json") as f:
    S = json.load(f)["specimens"]


def resample(xy, m=M):
    """m points equally spaced along the closed outline."""
    p = np.r_[xy, xy[:1]]
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(p, axis=0).T))]
    t = np.linspace(0, s[-1], m, endpoint=False)
    return np.interp(t, s, p[:, 0]), np.interp(t, s, p[:, 1])


def efd(x, y, n=N):
    """Elliptic Fourier coefficients a, b, c, d of harmonics 1..n (outline traversed counter-clockwise)."""
    x = x - x.mean(); y = y - y.mean(); m = len(x)
    if np.sum(x * np.roll(y, -1) - np.roll(x, -1) * y) < 0:
        x, y = x[::-1].copy(), y[::-1].copy()
    k = np.arange(1, n + 1)[:, None]
    w = 2 * np.pi * k * np.arange(m) / m
    sinc2 = (np.sin(np.pi * k / m) / (np.pi * k / m)) ** 2      # corrects for the sampling of the outline
    C, Sn = np.cos(w), np.sin(w)   # einsum, not @: Apple's Accelerate BLAS raises spurious overflow warnings here
    return [(2 / m) * sinc2[:, 0] * np.einsum("ki,i->k", T, u) for u, T in ((x, C), (x, Sn), (y, C), (y, Sn))]


def normalise(a, b, c, d):
    """The app's "as oriented": start where the first ellipse is above its centre, divide by its
    semi-major axis, keep the orientation. Returns the 4n-vector and the size."""
    th = np.arctan2(-a[0], b[0])
    if c[0] * np.cos(th) + d[0] * np.sin(th) < 0:
        th += np.pi
    th2 = 0.5 * np.arctan2(2 * (a[0] * b[0] + c[0] * d[0]), a[0]**2 + c[0]**2 - b[0]**2 - d[0]**2)
    ct, st = np.cos(th2), np.sin(th2)
    v1 = (a[0] * ct + b[0] * st)**2 + (c[0] * ct + d[0] * st)**2
    v2 = (-a[0] * st + b[0] * ct)**2 + (-c[0] * st + d[0] * ct)**2
    size = np.sqrt(max(v1, v2))
    h = np.arange(1, len(a) + 1); ch, sh = np.cos(h * th), np.sin(h * th)
    return np.r_[a * ch + b * sh, -a * sh + b * ch, c * ch + d * sh, -c * sh + d * ch] / size, size


def outline(v, P=300):
    """Reconstruct an outline from a normalised coefficient vector."""
    n = len(v) // 4; t = 2 * np.pi * np.arange(P + 1) / P; h = np.arange(1, n + 1)[:, None]
    return ((v[:n, None] * np.cos(h * t) + v[n:2*n, None] * np.sin(h * t)).sum(0),
            (v[2*n:3*n, None] * np.cos(h * t) + v[3*n:, None] * np.sin(h * t)).sum(0))


# Descriptors
raw = [np.array(s["outline"], float).reshape(-1, 2) for s in S]
groups = np.array([s["group"] for s in S]); stages = sorted(set(groups))
V, sizes = map(np.array, zip(*[normalise(*efd(*resample(xy))) for xy in raw]))
print("outlines", len(V), {g: int((groups == g).sum()) for g in stages})

# Raw extent of each outline, in the file's units
width = np.array([np.ptp(xy[:, 0]) for xy in raw]); ratio = np.array([np.ptp(xy[:, 1]) for xy in raw]) / width
for g in stages:
    k = groups == g
    print(f"{g}: width {width[k].min():.2f}-{width[k].max():.2f}, height/width mean {ratio[k].mean():.3f}")

# PCA on the 4N normalised coefficients
X = V - V.mean(0); U, sv, Wt = np.linalg.svd(X, full_matrices=False); var = sv**2 / (len(V) - 1); sc = U * sv
if np.corrcoef(sc[:, 0], np.log(sizes))[0, 1] < 0:      # fix PC1's arbitrary sign: positive = larger cephala
    sc[:, 0] *= -1; Wt[0] *= -1
print("variance share %", (100 * var / var.sum()).round(1)[:6])
first = Wt[0].reshape(4, N)[:, 0]
print("share of PC1's squared loading on harmonic 1: %.2f" % (first @ first))
print("Pearson r, PC1 vs height/width: %.2f" % np.corrcoef(sc[:, 0], ratio)[0, 1])
for g in stages:
    print(f"{g}: mean PC1 {sc[groups == g, 0].mean():.3f}")

# PC1 and size: pooled, and within stages (stage means removed)
print("Pearson r, PC1 vs log size: pooled %.2f" % np.corrcoef(sc[:, 0], np.log(sizes))[0, 1])
cen = lambda z: z - np.array([z[groups == g].mean() for g in groups])
print("  within stages %.2f" % np.corrcoef(cen(sc[:, 0]), cen(np.log(sizes)))[0, 1])


def loo(labels):
    """Leave-one-out: each outline goes to the nearest stage centroid on PC1-3, computed without it."""
    pred = []
    for i in range(len(V)):
        m = np.ones(len(V), bool); m[i] = False
        c = {g: sc[m & (labels == g), :3].mean(0) for g in stages}
        pred.append(min(c, key=lambda g: np.linalg.norm(sc[i, :3] - c[g])))
    return np.array(pred)


pred = loo(groups); ok = int((pred == groups).sum())
print(f"leave-one-out nearest centroid on PC1-3: {ok}/{len(V)} correct "
      f"(all to the most numerous stage: {max((groups == g).sum() for g in stages)}/{len(V)})")
print("confusion (rows true, columns predicted):")
for g in stages:
    print(" ", g, [int(((groups == g) & (pred == h)).sum()) for h in stages])

# Permutation test: the same classification with the stage labels shuffled
rng = np.random.default_rng(0); R = 1000
null = np.array([(loo(p) == p).sum() for p in (rng.permutation(groups) for _ in range(R))])
print(f"permutation null ({R} shuffles): mean {null.mean():.1f}, 95th percentile {np.percentile(null, 95):.0f}, "
      f"p(>= {ok}) = {(1 + (null >= ok).sum()) / (R + 1):.3f}")

# Stages a and b: distance between their centroids on PC1-3 against shuffles of the two labels
ab = np.isin(groups, ["stage a", "stage b"]); lab = groups[ab]; Z = sc[ab, :3]
dist = lambda l: np.linalg.norm(Z[l == "stage a"].mean(0) - Z[l == "stage b"].mean(0))
nd = np.array([dist(rng.permutation(lab)) for _ in range(R)])
print(f"stages a vs b, centroid distance on PC1-3: p = {(1 + (nd >= dist(lab)).sum()) / (R + 1):.2f}")

# Figure, light background
INK, MUTED = "#222222", "#777777"
cols = dict(zip(stages, ["#1b6ca8", "#3a9e5f", "#d98c1f", "#c23b3b"]))
names = {g: g.replace("stage ", "") + (" (largest)" if g == stages[0] else " (smallest)" if g == stages[-1] else "")
         for g in stages}
plt.rcParams.update({"font.size": 11, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
                     "xtick.color": MUTED, "ytick.color": MUTED, "axes.titlecolor": INK})
fig, ax = plt.subplots(1, 3, figsize=(15, 5))
for v, g in zip(V, groups):
    ax[0].plot(*outline(v), color=cols[g], lw=.5, alpha=.35)
for g in stages:
    ax[0].plot(*outline(V[groups == g].mean(0)), color=cols[g], lw=2.2, label=f"stage {names[g]}")
ax[0].set_aspect("equal"); ax[0].legend(frameon=False, loc="center", fontsize=10)
ax[0].set_title("a   outlines and stage means", loc="left")
for g in stages:
    ax[1].scatter(sc[groups == g, 0], sc[groups == g, 1], color=cols[g], s=26, label=f"stage {names[g]}")
ax[1].legend(frameon=False, fontsize=9, loc="lower left")
ax[1].set_xlabel(f"PC1 ({100 * var[0] / var.sum():.0f}% of shape variance)")
ax[1].set_ylabel(f"PC2 ({100 * var[1] / var.sum():.0f}%)")
ax[1].set_title("b   principal components", loc="left")
for s, c, ls, lab in [(-2, MUTED, "--", "PC1 −2 SD (smaller)"), (0, INK, "-", "mean shape"),
                      (2, INK, ":", "PC1 +2 SD (larger)")]:
    ax[2].plot(*outline(V.mean(0) + s * np.sqrt(var[0]) * Wt[0]), color=c, ls=ls, lw=1.8, label=lab)
ax[2].set_aspect("equal"); ax[2].legend(frameon=False, loc="center", fontsize=10)
ax[2].set_title("c   shape change along PC1", loc="left")
for a in (ax[0], ax[2]):
    a.set_xticks([]); a.set_yticks([]); [sp.set_visible(False) for sp in a.spines.values()]
plt.tight_layout(); plt.savefig("trilobites.png", dpi=110, facecolor="white")
