"""Precomputed shot × calibre terms, so that scoring with new weights is a few matrix operations.
    build/venv/bin/python fast.py <training> <data> [--rounds 3] [--out params.json]"""
import json, sys
import numpy as np
import kf, run

HIDDEN_SWITCH = "off"


class Pre:
    def __init__(self, shots):
        T = run.TABLES or run.Tables(run.CAT)
        run.TABLES = T
        self.T = T
        self.names, self.cals, self.parts_true = [], [], []
        rows = []
        for name, cal, part_true, m in shots:
            if m is None:
                continue
            self.names.append(name); self.cals.append(cal); self.parts_true.append(part_true)
            rows.append(self.terms(m, T))
        n = len(rows)
        keys = rows[0].keys()
        self.A = {k: np.stack([r[k] for r in rows]) for k in keys}
        self.n = n
        # Rows of the phone's list: allowed calibres per shot and twin groups.
        ids = T.ids
        sig_index = {}
        self.group = np.array([sig_index.setdefault(run.CAT.by_id[i]["sig"], len(sig_index)) for i in ids])
        self.ngroups = len(sig_index)
        rare = np.array([run.CAT.by_id[i]["rare"] for i in ids]); obs = np.array([run.CAT.by_id[i]["obsolete"] for i in ids])
        self.true_index = np.array([ids.index(c) for c in self.cals])
        allowed = []
        for c in self.cals:
            me = run.CAT.by_id[c]
            allowed.append(~((rare & ~me["rare"]) | (obs & ~me["obsolete"])))
        self.allowed = np.stack(allowed)
        self.allowed_all = np.ones_like(self.allowed)

    @staticmethod
    def terms(m, T):
        """Per calibre: aspect term, profile term each way, rim misfit each way, size differences."""
        part = run.part_of(m)
        out = {}
        for tag, (aspect, widths, rim, length, dia) in (("w", T.whole), ("c", T.case)):
            a = np.abs(np.log(m["aspect"] / aspect))
            ways = (m["widths"], m["widths"][::-1])
            prof = np.stack([np.nanmean(np.abs(w[None, :] - widths), axis=1) for w in ways])
            rimd = np.stack([np.abs(kf.features(w)["rim"] - rim) for w in ways])
            size = m.get("size")
            out[tag + "_a"] = a
            out[tag + "_prof"] = prof
            out[tag + "_rimd"] = rimd
            out[tag + "_len"] = length
            out[tag + "_dia"] = dia
        out["is_case"] = np.array(part == "case")
        out["first3"] = np.array(float(np.median(m["widths"][:3])))
        out["flat"] = np.array(bool(kf.features(m["widths"])["flat"]))
        out["has_size"] = np.array(bool(m.get("size")))
        out["L"] = np.array(m["size"]["length"] if m.get("size") else np.nan)
        out["p"] = np.array((m["length_px"] / m["aspect"]) / m["size"]["f"] if m.get("size") else 0.0)  # body width over focal length
        out["D"] = np.array(m["size"]["diameter"] if m.get("size") else np.nan)
        out["mouth"] = np.array(m["mouth"] if m.get("mouth") is not None else np.nan)
        return out

    def distances(self, P):
        A, T = self.A, self.T
        n = self.n
        is_case = A["is_case"][:, None]
        both = is_case  # an empty case may lie either way round
        def dist(tag, part_scale):
            nonlocal both
            a = A[tag + "_a"]
            prof = A[tag + "_prof"]; rimd = A[tag + "_rimd"]
            rim_pen = np.where(rimd <= P["rim_tol"], 0.0, P["w_rim"])
            d_ways = P["w_aspect"] * a[:, None, :] + P["w_profile"] * prof + rim_pen
            d = np.where(both, d_ways.min(1), d_ways[:, 0, :])
            p = A["p"][:, None]
            fr, bk = (T.front_whole, T.back_whole) if tag == "w" else (T.front_case, T.back_case)
            rise = (1 / (1 - fr[None, :] * p) + 1 / (1 - bk[None, :] * p)) / 2 if P.get("end_rise", 1) else 1.0
            L = A["L"][:, None] * part_scale / rise
            D = A["D"][:, None] * P["dia_scale"]
            size_pen = P["w_len"] * np.maximum(0, np.abs(L - A[tag + "_len"]) - P["tol_len"]) / 10 \
                + P["w_dia"] * np.maximum(0, np.abs(D - A[tag + "_dia"]) - P["tol_dia"]) / 10
            d = d + np.where(A["has_size"][:, None], np.nan_to_num(size_pen, nan=0.0), 0.0)
            return d
        if P.get("w_part", 0) > 0:
            # Soft: both comparisons, the end's width says which is more likely. A loaded round's tip
            # narrows (first slices well under the body), an empty case's mouth does not.
            first3 = A["first3"][:, None]
            pen_case = P["w_part"] * np.maximum(0, P["part_mid"] - first3)
            pen_whole = P["w_part"] * np.maximum(0, first3 - P["part_mid"]) * (~A["flat"][:, None] * 1.0 + A["flat"][:, None] * 2.0)
            both = np.ones_like(is_case)
        else:
            pen_case = np.zeros((n, 1)); pen_whole = np.zeros((n, 1))
        d_whole = dist("w", P["len_scale_whole"]) + pen_whole
        d_case = dist("c", P["len_scale_case"]) + pen_case
        if P.get("w_part", 0) > 0:
            d_case_ok = ~T.whole_only[None, :] & ~np.isnan(d_case)
            d = np.where(d_case_ok, np.minimum(d_whole, d_case), d_whole)
            is_case = np.where(d_case_ok, d_case < d_whole, False)  # per calibre: which comparison won
        else:
            d = np.where(is_case & ~T.whole_only[None, :] & ~np.isnan(d_case), d_case, d_whole)
        # Case mouth from the colours, on loaded rounds against calibres with a bullet.
        share = 1 - A["mouth"][:, None]
        has_mouth = (~np.isnan(A["mouth"]))[:, None] & ~is_case & T.has_mouth[None, :]
        # (With the soft part decision `is_case` is per calibre: the mouth only counts where the whole won.)
        pen = np.minimum(P["cap_mouth"], P["w_share"] * np.maximum(0, np.abs(share - (T.caselen / T.overall)[None, :]) - P["tol_share"]))
        case_mm = A["L"][:, None] * P["len_scale_whole"] * share
        pen_mm = np.minimum(P["cap_mouth"], P["w_caselen"] * np.maximum(0, np.abs(case_mm - T.caselen[None, :]) - P["tol_caselen"]) / 10)
        pen = pen + np.where(A["has_size"][:, None], np.nan_to_num(pen_mm, nan=0.0), 0.0)
        d = d + np.where(has_mouth, np.nan_to_num(pen, nan=0.0), 0.0)
        return d

    def rows(self, d, allowed):
        """Row of the true calibre in the phone's list (twins merged), per shot; 0 when not listed."""
        n = self.n
        dd = np.where(allowed & np.isfinite(d), d, np.inf)
        # Best distance per twin group.
        best = np.full((n, self.ngroups), np.inf)
        np.minimum.at(best.T, self.group, dd.T)  # best[:, g] = min over calibres in g
        true_g = self.group[self.true_index]
        d_true = best[np.arange(n), true_g]
        ahead = (best < d_true[:, None]).sum(1)
        listed = np.isfinite(d_true)
        return np.where(listed, ahead + 1, 0)

    def evaluate(self, P, idx=None):
        d = self.distances(P)
        r = self.rows(d, self.allowed)
        if idx is not None:
            r = r[idx]
        return (r == 1).mean(), ((r >= 1) & (r <= 5)).mean(), r


GRID = {
    "w_aspect": [0.5, 1, 2, 3, 4, 6, 8],
    "w_profile": [0, 0.5, 1, 2, 3, 4, 6],
    "w_len": [0, 0.5, 1, 2, 4, 8, 16],
    "w_dia": [0, 0.5, 1, 2, 4, 8, 16, 32],
    "tol_len": [0, 0.3, 0.5, 0.8, 1.0, 1.5, 2.0],
    "tol_dia": [0, 0.05, 0.1, 0.15, 0.2, 0.3, 0.5],
    "w_rim": [0, 0.05, 0.1, 0.2, 0.4, 0.8],
    "rim_tol": [0.03, 0.05, 0.08, 0.1, 0.15, 0.2],
    "len_scale_whole": [0.93, 0.94, 0.95, 0.96, 0.97, 0.98, 0.99, 1.0],
    "len_scale_case": [0.93, 0.94, 0.95, 0.96, 0.97, 0.98, 0.99, 1.0],
    "dia_scale": [0.98, 0.99, 1.0, 1.01, 1.02, 1.03, 1.05],
    "w_caselen": [0, 0.5, 1, 2, 4, 8, 16],
    "tol_caselen": [0.3, 0.5, 0.8, 1.0, 1.5, 2.0, 3.0],
    "w_share": [0, 0.5, 1, 2, 4, 8],
    "tol_share": [0.01, 0.02, 0.03, 0.05, 0.08],
    "w_part": [0, 0.5, 1, 2, 4, 8],
    "cap_mouth": [0.05, 0.1, 0.15, 0.2, 0.3, 0.5, 1.0],
    "end_rise": [0, 1],
    "part_mid": [0.45, 0.5, 0.55, 0.6, 0.65, 0.7],
}


def objective(pre, P, idx=None):
    t1, t5, r = pre.evaluate(P, idx)
    return t1 + 0.1 * t5


def search(pre, P, rounds, idx=None):
    best = objective(pre, P, idx)
    for _ in range(rounds):
        improved = False
        for key, values in GRID.items():
            for v in values:
                if v == P[key]:
                    continue
                Q = dict(P); Q[key] = v
                s = objective(pre, Q, idx)
                if s > best + 1e-9:
                    best, P, improved = s, Q, True
        if not improved:
            break
    return P, best


def restarts(pre, P0, rounds, idx=None, n=12, seed=0):
    """Coordinate search from P0 and from random grid points; the best fit wins."""
    rng = np.random.default_rng(seed)
    best = search(pre, dict(P0), rounds, idx)
    for _ in range(n):
        Q = {k: (rng.choice(v) if k in GRID else P0[k]) for k, v in {**P0, **GRID}.items()}
        Q = {k: Q[k] for k in P0}
        cand = search(pre, Q, rounds, idx)
        if cand[1] > best[1]:
            best = cand
    return best


if __name__ == "__main__":
    training, data = sys.argv[1], sys.argv[2]
    rounds = int(sys.argv[sys.argv.index("--rounds") + 1]) if "--rounds" in sys.argv else 3
    shots = run.load_all(training, data)
    pre = Pre(shots)
    P0 = dict(run.DEFAULT)
    t1, t5, _ = pre.evaluate(P0)
    print(f"{len(shots)} shots, {pre.n} measured; default: first {100*t1:.1f} % top5 {100*t5:.1f} %")
    P0.update({"len_scale_whole": 0.98, "len_scale_case": 0.98, "w_len": 2.0, "w_dia": 4.0, "end_rise": 1})
    P, best = restarts(pre, P0, rounds) if "--restarts" in sys.argv else search(pre, P0, rounds)
    t1, t5, r = pre.evaluate(P)
    total = len(shots)
    print(f"fit: first {100*t1:.1f} % top5 {100*t5:.1f} % of measured; of all {total}: first {100*(r==1).sum()/total:.1f} % top5 {100*((r>=1)&(r<=5)).sum()/total:.1f} %")
    print("params", json.dumps(P))
    pkgs = np.array([n.split("/")[0] for n in pre.names])
    hits1 = hits5 = 0
    for pkg in sorted(set(pkgs)):
        train = np.nonzero(pkgs != pkg)[0]; test = np.nonzero(pkgs == pkg)[0]
        Pp, _ = restarts(pre, P0, rounds, train, n=4) if "--restarts" in sys.argv else search(pre, P0, rounds, train)
        _, _, rr = pre.evaluate(Pp, test)
        h1, h5 = (rr == 1).sum(), ((rr >= 1) & (rr <= 5)).sum()
        hits1 += h1; hits5 += h5
        print(f"  held out {pkg:45s} {len(test):3d} shots  first {100*h1/len(test):5.1f} %  top5 {100*h5/len(test):5.1f} %")
    print(f"leave-one-package-out: first {100*hits1/pre.n:.1f} % top5 {100*hits5/pre.n:.1f} % of measured; of all: first {100*hits1/total:.1f} % top5 {100*hits5/total:.1f} %")
    if "--out" in sys.argv:
        json.dump(P, open(sys.argv[sys.argv.index("--out") + 1], "w"), indent=1)
    by = {}
    for name, cal, row in zip(pre.names, pre.cals, r):
        by.setdefault(cal, []).append(row)
    for cal, rs in sorted(by.items()):
        rs = np.array(rs)
        print(f"  {cal:32s} {len(rs):3d}  first {100*(rs==1).mean():5.1f} %  top5 {100*((rs>=1)&(rs<=5)).mean():5.1f} %")
