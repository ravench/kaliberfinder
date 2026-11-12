"""Refits the app's matcher weights on the terms its own pipeline measured (2026-11-12).

    .build/evaluate/evaluate <training> --terms terms-tuning.jsonl      # the app's terms per shot and calibre
    python3 tools/research/matcher/refit.py terms-tuning.jsonl [--check t-tuning.json] [--holdout terms-holdout.jsonl]
        [--golden terms-golden.jsonl] [--rounds 3] [--restarts 12] [--loo] [--out params.json]

The scoring here mirrors `Matcher.score` and `Matcher.distance` with every weight and tolerance a parameter
(`Matcher.swift`'s names), and the rows mirror `Evaluation.shot`: the phone's list with the switches off,
twins in one row, the shot's own calibre's switch on. `--check` proves the mirror against the tool's rows
before anything moves. The search is the coordinate search with random restarts of fast.py, objective
calibre first + 0.1 × top 5 on the tuning shots; `--loo` trains without each package and tests on it.
"""
import json
import sys

import numpy as np

# Matcher.swift today.
CURRENT = {
    "aspectWeight": 0.5, "profileWeight": 6.0, "rimPenalty": 0.05, "rimTolerance": 0.1, "missingRimWeight": 8.0,
    "lengthWeight": 2.0, "lengthTolerance": 2.0, "crimpRangeWeight": 0.25, "diameterWeight": 1.0, "diameterTolerance": 0.3,
    "lengthScaleWhole": 0.98, "lengthScaleCase": 0.96, "diameterScale": 1.02, "partWeight": 0.5, "partMiddle": 0.7,
    "shareWeight": 0.5, "shareTolerance": 0.03, "caseLengthWeight": 0.5, "caseLengthTolerance": 0.3, "mouthCap": 0.05,
    "neckPenalty": 0.3, "neckTolerance": 0.15, "maxBehindBest": 0.5, "maxDistance": 1.5,
}
GRID = {
    "aspectWeight": [0.25, 0.5, 1, 2, 3, 4, 6], "profileWeight": [2, 3, 4, 6, 8, 10, 12],
    "rimPenalty": [0, 0.05, 0.1, 0.2, 0.4], "rimTolerance": [0.05, 0.08, 0.1, 0.15, 0.2], "missingRimWeight": [0, 2, 4, 8, 12, 16],
    "lengthWeight": [0, 0.5, 1, 2, 4, 8], "lengthTolerance": [0, 0.5, 1, 1.5, 2, 3], "crimpRangeWeight": [0, 0.25, 0.5, 1],
    "diameterWeight": [0, 0.5, 1, 2, 4, 8], "diameterTolerance": [0, 0.1, 0.2, 0.3, 0.5],
    "lengthScaleWhole": [0.95, 0.96, 0.97, 0.98, 0.99, 1.0], "lengthScaleCase": [0.94, 0.95, 0.96, 0.97, 0.98, 0.99, 1.0],
    "diameterScale": [0.98, 0.99, 1.0, 1.01, 1.02, 1.03, 1.04], "partWeight": [0, 0.25, 0.5, 1, 2], "partMiddle": [0.5, 0.55, 0.6, 0.65, 0.7, 0.75],
    "shareWeight": [0, 0.5, 1, 2, 4], "shareTolerance": [0.01, 0.02, 0.03, 0.05, 0.08], "caseLengthWeight": [0, 0.5, 1, 2, 4],
    "caseLengthTolerance": [0.3, 0.5, 1, 1.5, 2], "mouthCap": [0.02, 0.05, 0.1, 0.2, 0.3, 0.5],
    "neckPenalty": [0, 0.1, 0.3, 0.6], "neckTolerance": [0.05, 0.1, 0.15, 0.2, 0.3],
}
SHOWN_LIMIT = 12
PARTS = ("w", "c", "h")
TERM_KEYS = ("a", "prof0", "prof1", "rimd0", "rimd1", "missing", "len", "lo", "hi", "dia", "front", "back")


def array(values):
    return np.array([np.nan if v is None else v for v in values], dtype=np.float32)


class Terms:
    """The dump of one set of shots: catalogue facts (per calibre) and per shot the photo and the terms."""

    def __init__(self, path):
        with open(path) as f:
            lines = [json.loads(line) for line in f if line.strip()]
        cat = lines[0]["catalogue"]
        self.ids = [c["id"] for c in cat]
        self.m = len(cat)
        for key in ("rare", "obsolete", "hasCase", "shot", "wholeOnly", "hasWhole", "wholeEndView", "hasCaseShape", "caseEndView"):
            setattr(self, key, np.array([c[key] for c in cat]))
        self.group = np.array([c["group"] for c in cat])
        self.caseLength = array([c["case"] for c in cat])
        self.overall = array([c["overall"] for c in cat])
        self.neckRatio = array([c["neckRatio"] for c in cat])
        self.hasBullet = self.hasCase & ~self.wholeOnly
        shots = lines[1:]
        self.n = len(shots)
        self.names = [s["name"] for s in shots]
        self.packages = np.array([n.split("/")[0] for n in self.names])
        self.calibre = [s["calibre"] for s in shots]
        self.true = np.array([self.ids.index(c) for c in self.calibre])
        self.endView = np.array([s["endView"] for s in shots])
        self.end = array([s["end"] for s in shots])
        self.decided = np.array([s["decided"] or "" for s in shots])
        self.brass = np.array([s["brass"] for s in shots])
        self.L = array([s["L"] for s in shots])
        self.D = array([s["D"] for s in shots])
        self.p = array([s["p"] for s in shots])
        self.mouth = array([s["mouth"] for s in shots])
        self.neck = array([s["neck"] for s in shots])
        self.t = {f"{tag}_{k}": np.stack([array(s[f"{tag}_{k}"]) for s in shots]) for tag in PARTS for k in TERM_KEYS}
        # What the phone hides with the switches off, the shot's own calibre's switch on.
        true_rare, true_obs = self.rare[self.true], self.obsolete[self.true]
        self.allowed = ~((self.rare[None, :] & ~true_rare[:, None]) | (self.obsolete[None, :] & ~true_obs[:, None]))
        self.ngroups = int(self.group.max()) + 1

    def distance(self, P, tag, scale):
        """`Matcher.distance` for one part of every calibre: shape, rim, and the LiDAR size where there is one."""
        t = self.t
        a, prof0, prof1 = t[f"{tag}_a"], t[f"{tag}_prof0"], t[f"{tag}_prof1"]
        rimd0, rimd1 = t[f"{tag}_rimd0"], t[f"{tag}_rimd1"]
        pen0 = np.where(np.nan_to_num(rimd0, nan=0) > P["rimTolerance"], P["rimPenalty"], 0.0)
        pen1 = np.where(np.nan_to_num(rimd1, nan=0) > P["rimTolerance"], P["rimPenalty"], 0.0)
        d0 = P["aspectWeight"] * a + P["profileWeight"] * prof0 + pen0
        d1 = P["aspectWeight"] * a + P["profileWeight"] * prof1 + pen1
        d = np.where(np.isnan(d1), d0, np.minimum(d0, d1))
        d = d + P["missingRimWeight"] * np.maximum(0, np.nan_to_num(t[f"{tag}_missing"], nan=-np.inf) - P["rimTolerance"])
        p = self.p[:, None]
        rise = np.where((p > 0) & (p < 0.5), (1 / (1 - t[f"{tag}_front"] * p) + 1 / (1 - t[f"{tag}_back"] * p)) / 2, 1.0)
        length = self.L[:, None] * scale / rise
        lo, hi, expected = t[f"{tag}_lo"], t[f"{tag}_hi"], t[f"{tag}_len"]
        outside = np.maximum(np.maximum(lo - length, length - hi), 0)
        length_off = np.maximum(0, outside - P["lengthTolerance"])
        from_catalogue = np.maximum(0, np.abs(length - expected) - P["lengthTolerance"]) - length_off
        dia_off = np.maximum(0, np.abs(self.D[:, None] * P["diameterScale"] - t[f"{tag}_dia"]) - P["diameterTolerance"])
        size = P["lengthWeight"] * (length_off + P["crimpRangeWeight"] * from_catalogue) / 10 + P["diameterWeight"] * dia_off / 10
        return d + np.where(np.isnan(self.L)[:, None], 0.0, np.nan_to_num(size, nan=0.0))

    def distances(self, P):
        """`Matcher.score` for every shot and calibre: the best of the parts in play; nan where nothing compares."""
        n, m = self.n, self.m
        has_bullet = self.hasBullet[None, :]
        decided = np.where(has_bullet, self.decided[:, None], "")
        case_only = decided == "emptyCase"
        undecided = decided == ""
        neck = np.where(~np.isnan(self.neck)[:, None] & (self.neckRatio[None, :] > self.neck[:, None] + P["neckTolerance"]), P["neckPenalty"], 0.0)
        end = self.end[:, None]
        share = 1 - self.mouth[:, None]
        expected_share = (self.caseLength / self.overall)[None, :]
        mouth_pen = np.minimum(P["mouthCap"], P["shareWeight"] * np.maximum(0, np.abs(share - expected_share) - P["shareTolerance"]))
        case_mm = self.L[:, None] * P["lengthScaleWhole"] * share
        mouth_pen = mouth_pen + np.where(np.isnan(self.L)[:, None], 0.0, np.nan_to_num(
            np.minimum(P["mouthCap"], P["caseLengthWeight"] * np.maximum(0, np.abs(case_mm - self.caseLength[None, :]) - P["caseLengthTolerance"]) / 10), nan=0.0))
        has_mouth = ~np.isnan(self.mouth)[:, None] & has_bullet
        inf = np.full((n, m), np.inf, dtype=np.float32)
        whole_ok = (~case_only | ~self.hasCaseShape[None, :]) & self.hasWhole[None, :] & ~self.wholeEndView[None, :]
        d_w = self.distance(P, "w", P["lengthScaleWhole"]) + np.where(has_bullet & undecided, P["partWeight"] * np.maximum(0, end - P["partMiddle"]), 0.0) \
            + np.where(has_mouth, mouth_pen, 0.0) + neck
        d_w = np.where(whole_ok, np.nan_to_num(d_w, nan=np.inf), inf)
        hull_ok = self.shot[None, :] & self.hasWhole[None, :] & ~self.wholeEndView[None, :]
        d_h = np.where(hull_ok, np.nan_to_num(self.distance(P, "h", P["lengthScaleWhole"]) + neck, nan=np.inf), inf)
        case_ok = (decided != "cartridge") & self.hasCaseShape[None, :] & ~self.caseEndView[None, :]
        d_c = self.distance(P, "c", P["lengthScaleCase"]) + np.where(undecided, P["partWeight"] * np.maximum(0, P["partMiddle"] - end), 0.0) + neck
        d_c = np.where(case_ok, np.nan_to_num(d_c, nan=np.inf), inf)
        d = np.minimum(np.minimum(d_w, d_h), d_c)
        # An end view compares with round things only: aspect and profile of the whole, nothing else.
        end_d = P["aspectWeight"] * self.t["w_a"] + P["profileWeight"] * self.t["w_prof0"]
        end_d = np.where(self.wholeEndView[None, :], np.nan_to_num(end_d, nan=np.inf), inf)
        d = np.where(self.endView[:, None], end_d, d)
        # A brass-coloured object is no ball, Minié bullet or pellet.
        d = np.where(self.brass[:, None] & ~self.hasCase[None, :], inf, d)
        return d

    def rows(self, P, d=None):
        """The row of the shot's calibre in the phone's list (switches off), 0 when not in the first twelve."""
        if d is None:
            d = self.distances(P)
        best = d.min(1)
        cut = np.minimum(P["maxDistance"], best + P["maxBehindBest"])
        listed = np.isfinite(d) & (self.endView[:, None] | (d <= cut[:, None])) & self.allowed
        dd = np.where(listed, d, np.inf)
        # The first twelve of the list, then twins (groupedByProfile) share a row in rank order.
        order = np.argsort(dd, axis=1, kind="stable")[:, :SHOWN_LIMIT]
        shown = np.take_along_axis(dd, order, 1)
        groups = self.group[order]
        rows = np.zeros(self.n, dtype=int)
        true_group = self.group[self.true]
        for i in range(self.n):
            seen = []
            row = 0
            for g, value in zip(groups[i], shown[i]):
                if not np.isfinite(value):
                    break
                if g not in seen:
                    seen.append(g)
                if g == true_group[i]:
                    row = seen.index(g) + 1
                    break
            rows[i] = row
        return rows

    def scores(self, P, idx=None):
        r = self.rows(P)
        if idx is not None:
            r = r[idx]
        return (r == 1).mean(), ((r >= 1) & (r <= 5)).mean(), r


def objective(terms, P, idx=None):
    t1, t5, _ = terms.scores(P, idx)
    return t1 + 0.1 * t5


def search(terms, P, rounds, idx=None):
    best = objective(terms, P, idx)
    for _ in range(rounds):
        improved = False
        for key, values in GRID.items():
            for v in values:
                if v == P[key]:
                    continue
                Q = dict(P)
                Q[key] = v
                s = objective(terms, Q, idx)
                if s > best + 1e-9:
                    best, P, improved = s, Q, True
        if not improved:
            break
    return P, best


def restarts(terms, P0, rounds, idx=None, n=12, seed=0):
    rng = np.random.default_rng(seed)
    best = search(terms, dict(P0), rounds, idx)
    for _ in range(n):
        Q = {k: (float(rng.choice(v)) if k in GRID else P0[k]) for k, v in {**P0, **GRID}.items()}
        Q = {k: Q[k] for k in P0}
        cand = search(terms, Q, rounds, idx)
        if cand[1] > best[1]:
            best = cand
    return best


def report(label, terms, P):
    t1, t5, _ = terms.scores(P)
    print(f"{label:28s} {terms.n:4d} shots: first {100*t1:5.1f} %  top 5 {100*t5:5.1f} %")


if __name__ == "__main__":
    args = sys.argv[1:]
    def option(name, default=None):
        return args[args.index(name) + 1] if name in args else default
    tuning = Terms(args[0])
    print(f"{tuning.n} tuning shots, {tuning.m} calibres")
    if check := option("--check"):
        tool = json.load(open(check))["shots"]
        rows = tuning.rows(CURRENT)
        same = sum(1 for name, r in zip(tuning.names, rows) if (tool[name].get("row") or 0) == r)
        print(f"mirror check: {same} of {tuning.n} rows agree with the tool", "" if same == tuning.n else "<<< MISMATCH")
        for name, r in zip(tuning.names, rows):
            if (tool[name].get("row") or 0) != r:
                print(f"  {name}: tool row {tool[name].get('row')} here {r}")
                break
    holdout = Terms(option("--holdout")) if option("--holdout") else None
    golden = Terms(option("--golden")) if option("--golden") else None
    rounds, n_restarts = int(option("--rounds", 3)), int(option("--restarts", 12))
    report("current, tuning", tuning, CURRENT)
    if holdout: report("current, held back", holdout, CURRENT)
    if golden: report("current, golden", golden, CURRENT)
    P, best = restarts(tuning, dict(CURRENT), rounds, n=n_restarts)
    print("fitted:", json.dumps({k: v for k, v in P.items() if v != CURRENT[k]}))
    report("fitted, tuning", tuning, P)
    if holdout: report("fitted, held back", holdout, P)
    if golden: report("fitted, golden", golden, P)
    if "--loo" in args:
        hits1 = hits5 = 0
        for pkg in sorted(set(tuning.packages)):
            train = np.nonzero(tuning.packages != pkg)[0]; test = np.nonzero(tuning.packages == pkg)[0]
            Pp, _ = search(tuning, dict(CURRENT), rounds, train)
            _, _, rr = tuning.scores(Pp, test)
            h1, h5 = int((rr == 1).sum()), int(((rr >= 1) & (rr <= 5)).sum())
            hits1 += h1; hits5 += h5
            print(f"  held out {pkg:44s} {len(test):3d} shots  first {100*h1/len(test):5.1f} %  top 5 {100*h5/len(test):5.1f} %")
        print(f"leave-one-package-out: first {100*hits1/tuning.n:.1f} %  top 5 {100*hits5/tuning.n:.1f} %")
    if out := option("--out"):
        json.dump(P, open(out, "w"), indent=1)
