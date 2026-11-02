"""Calibre catalogue with approximate cartridge dimensions (mm, CIP/SAAMI-ish).

Used by generate_assets.py to draw a side-view outline for every calibre.
Dimensions are approximations for an icon, not reloading data.
"""

# Kinds
RIMLESS, RIMMED, BELTED, RIMFIRE, SHOT, BALL, MINIE, PELLET = (
    "rimless", "rimmed", "belted", "rimfire", "shot", "ball", "minie", "pellet")
# Bullet profiles
SPITZER, ROUND, FLAT = "spitzer", "round", "flat"


def c(name, kind, rim, base, shoulder, neck, case, sh_at, oal, bullet, profile, aliases=()):
    return dict(name=name, kind=kind, rim=rim, base=base, shoulder=shoulder, neck=neck,
                case=case, sh_at=sh_at, oal=oal, bullet=bullet, profile=profile, aliases=list(aliases))


def straight(name, kind, rim, base, neck, case, oal, bullet, profile, aliases=()):
    return c(name, kind, rim, base, None, neck, case, None, oal, bullet, profile, aliases)


def shot(name, dia, rim, length, aliases=()):
    return c(name, SHOT, rim, dia, None, dia, length, None, length, dia, FLAT, aliases)


def ball(name, dia, aliases=()):
    return c(name, BALL, dia, dia, None, dia, 0, None, dia, dia, ROUND, aliases)


def minie(name, dia, length, aliases=()):
    return c(name, MINIE, dia, dia, None, dia, 0, None, length, dia, ROUND, aliases)


def pellet(name, dia, length, aliases=()):
    return c(name, PELLET, dia, dia, None, dia, 0, None, length, dia, ROUND, aliases)


CATALOGUE = [
    ("Randfeuer", [
        straight(".22 Short", RIMFIRE, 6.9, 5.7, 5.7, 10.7, 17.7, 5.7, ROUND),
        straight(".22 LR", RIMFIRE, 6.9, 5.7, 5.7, 15.6, 25.4, 5.7, ROUND, ["22lr", "22", "kk", "22l.r."]),
        straight(".22 WMR", RIMFIRE, 7.5, 6.1, 6.1, 26.8, 32.3, 5.7, SPITZER, ["22mag", "22wmr"]),
        c(".17 HMR", RIMFIRE, 7.5, 6.1, 6.1, 4.5, 26.9, 21.5, 32.8, 4.4, SPITZER, ["17hmr"]),
        c(".17 Mach 2", RIMFIRE, 6.9, 5.7, 5.7, 4.5, 18.0, 13.5, 25.0, 4.4, SPITZER),
    ]),
    ("Kurzwaffe", [
        straight("6.35 mm Browning (.25 ACP)", RIMLESS, 7.6, 7.1, 7.0, 15.6, 23.1, 6.4, ROUND, ["6.35", "25acp", "25auto"]),
        straight("7.65 mm Browning (.32 ACP)", RIMLESS, 9.1, 8.6, 8.5, 17.3, 25.0, 7.9, ROUND, ["7.65browning", "32acp", "32auto"]),
        c("7.65 mm Parabellum", RIMLESS, 9.9, 9.9, 9.7, 8.4, 21.6, 15.0, 29.8, 7.85, ROUND, ["7.65para", "30luger"]),
        straight(".32 S&W Long", RIMMED, 9.5, 8.6, 8.5, 23.4, 32.5, 7.9, ROUND, ["32s&w", "32swl", "32long"]),
        straight(".32 H&R Magnum", RIMMED, 9.5, 8.6, 8.5, 27.4, 34.3, 7.9, FLAT),
        c("7.62x25 mm Tokarev", RIMLESS, 9.9, 9.9, 9.6, 8.5, 24.7, 17.5, 34.9, 7.85, ROUND, ["tokarev", "7.62tok"]),
        straight("9 mm Browning kurz (.380 ACP)", RIMLESS, 9.5, 9.5, 9.4, 17.3, 25.0, 9.0, ROUND, ["380acp", "380auto", "9kurz", "9mmkurz"]),
        straight("9x18 mm Makarov", RIMLESS, 9.9, 9.9, 9.7, 18.1, 25.0, 9.27, ROUND, ["makarov"]),
        straight("9x19 mm", RIMLESS, 9.96, 9.96, 9.65, 19.15, 29.7, 9.01, ROUND, ["9x19", "9mm", "9mmpara", "9para", "9mmluger", "9luger", "9x19para", "parabellum"]),
        straight("9x21 mm IMI", RIMLESS, 9.96, 9.96, 9.65, 21.15, 29.7, 9.01, ROUND, ["9x21"]),
        c(".357 SIG", RIMLESS, 10.77, 10.77, 10.7, 9.68, 21.97, 15.8, 28.96, 9.02, ROUND, ["357sig"]),
        straight(".38 Special", RIMMED, 11.2, 9.6, 9.6, 29.3, 39.4, 9.07, ROUND, ["38spl", "38special", "38"]),
        straight(".357 Magnum", RIMMED, 11.2, 9.6, 9.6, 32.8, 40.6, 9.07, FLAT, ["357mag", "357", "357magnum"]),
        straight(".38 Super", RIMLESS, 10.2, 9.7, 9.6, 22.9, 32.5, 9.03, ROUND, ["38super"]),
        straight("10 mm Auto", RIMLESS, 10.8, 10.8, 10.7, 25.2, 32.0, 10.17, FLAT, ["10mm", "10auto"]),
        straight(".40 S&W", RIMLESS, 10.8, 10.8, 10.7, 21.6, 28.8, 10.17, FLAT, ["40s&w", "40sw", "40"]),
        straight(".41 Magnum", RIMMED, 13.0, 11.0, 11.0, 32.8, 40.4, 10.4, FLAT, ["41mag"]),
        straight(".44 Special", RIMMED, 13.1, 11.6, 11.6, 29.5, 37.0, 10.9, FLAT, ["44spl", "44special"]),
        straight(".44 Magnum", RIMMED, 13.1, 11.6, 11.6, 32.6, 40.9, 10.9, FLAT, ["44mag", "44magnum"]),
        straight(".45 ACP", RIMLESS, 12.0, 12.0, 12.0, 22.8, 32.4, 11.5, ROUND, ["45acp", "45auto", "45", "11.43"]),
        straight(".45 Colt", RIMMED, 12.9, 12.2, 12.2, 32.6, 40.6, 11.5, FLAT, ["45colt", "45lc", "45longcolt"]),
        straight(".45 GAP", RIMLESS, 12.0, 12.0, 12.0, 19.2, 27.3, 11.5, ROUND, ["45gap"]),
        straight(".454 Casull", RIMMED, 13.1, 12.1, 12.1, 35.1, 45.0, 11.5, FLAT, ["454casull"]),
        straight(".460 S&W Magnum", RIMMED, 13.2, 12.2, 12.2, 45.7, 58.0, 11.5, FLAT, ["460s&w"]),
        straight(".500 S&W Magnum", RIMMED, 14.2, 13.4, 13.4, 41.3, 57.2, 12.7, FLAT, ["500s&w"]),
        c("5.7x28 mm", RIMLESS, 7.9, 7.9, 7.8, 6.4, 28.9, 22.5, 40.5, 5.7, SPITZER, ["5.7x28", "57x28"]),
        c("4.6x30 mm", RIMLESS, 8.0, 8.0, 7.8, 5.3, 30.5, 24.0, 38.7, 4.65, SPITZER, ["4.6x30"]),
    ]),
    ("Langwaffe", [
        c(".204 Ruger", RIMLESS, 9.6, 9.6, 9.3, 6.0, 47.0, 38.5, 57.4, 5.2, SPITZER),
        c(".222 Remington", RIMLESS, 9.6, 9.6, 9.1, 6.4, 43.2, 34.0, 54.0, 5.7, SPITZER, ["222rem"]),
        c(".223 Remington", RIMLESS, 9.6, 9.6, 9.0, 6.4, 44.7, 36.0, 57.4, 5.7, SPITZER, ["223", "223rem"]),
        c("5.56x45 mm NATO", RIMLESS, 9.6, 9.6, 9.0, 6.4, 44.7, 36.0, 57.4, 5.7, SPITZER, ["5.56", "556", "5.56x45", "5.56nato"]),
        c("5.6 mm GP 90 (Swiss)", RIMLESS, 9.6, 9.6, 9.0, 6.4, 44.7, 36.0, 57.4, 5.7, SPITZER, ["gp90", "gp 90", "5.6", "5.6mm", "5.6gp90", "stgw90"]),
        c(".22-250 Remington", RIMLESS, 12.0, 12.0, 11.5, 6.6, 48.6, 39.0, 60.3, 5.7, SPITZER, ["22-250"]),
        c(".243 Winchester", RIMLESS, 12.0, 12.0, 11.5, 7.0, 51.9, 41.0, 68.8, 6.2, SPITZER, ["243", "243win"]),
        c("6 mm BR Norma", RIMLESS, 12.0, 12.0, 11.6, 6.9, 39.6, 31.5, 58.0, 6.2, SPITZER, ["6br", "6mmbr"]),
        c("6 mm ARC", RIMLESS, 11.2, 11.2, 10.9, 6.9, 38.6, 31.8, 57.4, 6.2, SPITZER, ["6arc"]),
        c("6.5 mm Creedmoor", RIMLESS, 12.0, 12.0, 11.7, 7.5, 48.8, 39.6, 71.8, 6.7, SPITZER, ["6.5cm", "6.5creedmoor", "65cm", "creedmoor"]),
        c("6.5x55 mm Swedish", RIMLESS, 12.2, 12.2, 11.0, 7.6, 55.0, 44.6, 80.0, 6.7, SPITZER, ["6.5x55", "6.5x55se"]),
        c("6.5x47 mm Lapua", RIMLESS, 12.0, 12.0, 11.6, 7.5, 47.0, 38.2, 72.0, 6.7, SPITZER, ["6.5x47"]),
        c("6.5 PRC", RIMLESS, 13.0, 13.0, 12.8, 7.5, 51.2, 41.8, 84.8, 6.7, SPITZER, ["6.5prc"]),
        c(".260 Remington", RIMLESS, 12.0, 12.0, 11.5, 7.5, 51.7, 41.0, 71.1, 6.7, SPITZER),
        c(".270 Winchester", RIMLESS, 12.0, 12.0, 11.2, 7.8, 64.5, 52.6, 84.8, 7.0, SPITZER, ["270", "270win"]),
        c("7 mm-08 Remington", RIMLESS, 12.0, 12.0, 11.5, 8.0, 51.7, 41.0, 71.1, 7.2, SPITZER, ["7mm-08", "7-08"]),
        c("7x57 mm Mauser", RIMLESS, 12.0, 12.0, 10.9, 8.2, 57.0, 45.5, 78.0, 7.24, SPITZER, ["7x57"]),
        c("7x64 mm", RIMLESS, 12.0, 12.0, 11.3, 8.0, 64.0, 52.0, 84.0, 7.24, SPITZER, ["7x64"]),
        c("7 mm Remington Magnum", BELTED, 13.5, 13.0, 12.4, 8.0, 63.5, 54.0, 82.6, 7.2, SPITZER, ["7mmremmag", "7rm"]),
        c("7 mm PRC", RIMLESS, 13.4, 13.4, 13.0, 8.0, 63.5, 54.0, 90.3, 7.2, SPITZER, ["7prc"]),
        c("7.5x55 mm Swiss (GP 11)", RIMLESS, 12.6, 12.6, 11.6, 8.5, 55.6, 45.0, 77.5, 7.77, SPITZER, ["gp11", "gp 11", "7.5x55", "7.5", "7.5mm", "7.5swiss", "k31"]),
        c("7.5x54 mm French", RIMLESS, 12.25, 12.25, 11.2, 8.6, 54.0, 44.0, 76.0, 7.8, SPITZER, ["7.5x54"]),
        c("7.62x39 mm", RIMLESS, 11.35, 11.35, 10.07, 8.6, 38.7, 30.5, 56.0, 7.9, SPITZER, ["7.62x39", "762x39"]),
        c(".300 AAC Blackout", RIMLESS, 9.6, 9.6, 9.1, 8.4, 34.7, 31.0, 57.0, 7.8, SPITZER, ["300blk", "300blackout", "300aac"]),
        c("7.62x51 mm NATO", RIMLESS, 11.9, 11.9, 11.5, 8.7, 51.2, 39.6, 71.1, 7.82, SPITZER, ["7.62x51", "7.62nato", "762"]),
        c(".308 Winchester", RIMLESS, 11.9, 11.9, 11.5, 8.7, 51.2, 39.6, 71.1, 7.82, SPITZER, ["308", "308win"]),
        c(".30-06 Springfield", RIMLESS, 12.0, 12.0, 11.2, 8.6, 63.3, 49.5, 84.8, 7.82, SPITZER, ["30-06", "3006"]),
        c(".30-30 Winchester", RIMMED, 12.8, 10.7, 10.2, 8.5, 51.8, 38.5, 64.8, 7.82, FLAT, ["30-30", "3030"]),
        c(".300 Winchester Magnum", BELTED, 13.0, 13.0, 12.4, 8.6, 66.7, 58.5, 84.8, 7.82, SPITZER, ["300winmag", "300wm"]),
        c(".300 PRC", RIMLESS, 13.4, 13.4, 13.0, 8.6, 70.4, 59.0, 94.5, 7.82, SPITZER, ["300prc"]),
        c(".300 Norma Magnum", RIMLESS, 14.9, 14.9, 14.4, 8.6, 63.3, 54.0, 91.4, 7.82, SPITZER, ["300norma", "300nm"]),
        c(".303 British", RIMMED, 13.5, 11.7, 10.2, 8.6, 56.4, 42.5, 78.1, 7.92, SPITZER, ["303", "303brit"]),
        c("7.62x54 mm R", RIMMED, 14.5, 12.4, 11.6, 8.5, 53.6, 41.0, 77.2, 7.92, SPITZER, ["7.62x54r", "762x54r"]),
        c("8x57 mm IS", RIMLESS, 11.95, 11.95, 11.0, 9.1, 57.0, 47.0, 82.0, 8.2, SPITZER, ["8x57", "8x57is", "8mmmauser"]),
        c("8x68 mm S", RIMLESS, 13.3, 13.3, 12.4, 9.2, 67.5, 56.5, 87.5, 8.2, SPITZER, ["8x68"]),
        c("9.3x62 mm", RIMLESS, 12.0, 12.0, 11.5, 10.0, 62.0, 52.0, 83.6, 9.3, ROUND, ["9.3x62"]),
        c("9.3x74 mm R", RIMMED, 13.0, 11.9, 10.8, 10.0, 74.0, 58.0, 94.5, 9.3, ROUND, ["9.3x74r"]),
        c(".338 Lapua Magnum", RIMLESS, 14.9, 14.9, 14.4, 9.3, 69.2, 57.5, 93.5, 8.6, SPITZER, ["338lm", "338lapua", "338"]),
        c(".375 H&H Magnum", BELTED, 13.0, 13.0, 11.6, 10.3, 72.4, 62.0, 91.4, 9.5, ROUND, ["375h&h", "375hh"]),
        c(".416 Rigby", RIMLESS, 14.9, 14.9, 13.6, 11.6, 73.7, 59.0, 95.3, 10.6, ROUND, ["416rigby"]),
        straight(".45-70 Government", RIMMED, 15.2, 12.7, 12.2, 53.5, 64.8, 11.6, FLAT, ["45-70", "4570"]),
        c(".50 BMG", RIMLESS, 20.4, 20.4, 18.3, 14.0, 99.0, 76.0, 138.0, 12.98, SPITZER, ["50bmg", "12.7x99"]),
    ]),
    ("Schwarzpulver", [
        ball(".36 Rundkugel (.375)", 9.5, ["36", "36navy", ".375ball"]),
        ball(".44 Rundkugel (.454)", 11.5, ["44", "44ball", ".454", "454ball"]),
        ball(".45 Rundkugel (.440)", 11.2, ["45ball", ".440"]),
        ball(".50 Rundkugel (.490)", 12.4, ["50", "50ball", ".490"]),
        ball(".54 Rundkugel (.530)", 13.5, ["54", "54ball", ".530"]),
        minie(".58 Minié", 14.6, 25.0, ["58", "58minie"]),
        minie(".69 Minié", 17.3, 27.0, ["69", "69minie"]),
        c("10.4x38 mm R Vetterli", RIMMED, 17.6, 14.4, 13.4, 11.4, 38.0, 25.0, 58.5, 10.8, ROUND, ["vetterli", "10.4", "10.4vetterli", "10.4x38"]),
        straight(".577 Snider", RIMMED, 19.2, 17.0, 16.4, 50.8, 62.0, 14.6, ROUND, ["577snider"]),
        c(".577/450 Martini-Henry", RIMMED, 19.0, 17.0, 16.0, 12.3, 59.7, 38.0, 79.0, 11.6, ROUND, ["martini-henry", "577/450"]),
        straight(".50-70 Government", RIMMED, 16.9, 14.2, 13.4, 44.5, 57.0, 13.0, ROUND, ["50-70"]),
        c(".44-40 WCF", RIMMED, 13.1, 11.9, 11.5, 11.1, 33.2, 22.0, 40.6, 10.8, FLAT, ["44-40", "4440"]),
    ]),
    ("Flinte", [
        shot("12/70", 20.6, 22.3, 64.0, ["12", "12/70", "12ga", "12gauge"]),
        shot("12/76", 20.6, 22.3, 70.0, ["12/76"]),
        shot("12/89", 20.6, 22.3, 82.0, ["12/89"]),
        shot("16/70", 18.9, 20.5, 64.0, ["16", "16/70"]),
        shot("20/70", 17.6, 19.0, 64.0, ["20", "20/70"]),
        shot("20/76", 17.6, 19.0, 70.0, ["20/76"]),
        shot("28/70", 16.0, 17.5, 64.0, ["28", "28/70"]),
        shot(".410/76", 11.8, 13.3, 70.0, [".410", "410"]),
    ]),
    ("Luftdruck", [
        pellet("4.5 mm Diabolo (.177)", 4.5, 5.5, ["4.5", "4.5mm", "177", "luftgewehr", "lg", "lp"]),
        pellet("5.5 mm Diabolo (.22)", 5.5, 6.5, ["5.5", "5.5mm"]),
    ]),
]

# Printable alternative names (max 2), shown in the app's calibre lists and search,
# and on the calibre poster. Never alias calibres that are separate cartridges:
# .223 Rem / 5.56 NATO / GP 90 and .308 Win / 7.62 NATO differ in loading and are
# not necessarily interchangeable, so each stays its own entry.
DISPLAY_ALIASES = {
    ".22 LR": [".22 Long Rifle", "KK"],
    ".22 WMR": [".22 Magnum"],
    "7.65 mm Browning (.32 ACP)": [".32 ACP", ".32 Auto"],
    "7.65 mm Parabellum": [".30 Luger"],
    "9 mm Browning kurz (.380 ACP)": [".380 ACP", ".380 Auto"],
    "9x19 mm": ["9 mm Luger", "9 mm Para"],
    ".38 Special": [".38 Spl"],
    ".45 ACP": [".45 Auto", "11,43 mm"],
    ".45 Colt": [".45 Long Colt"],
    ".30-06 Springfield": ["7.62x63 mm"],
    ".300 AAC Blackout": [".300 BLK", "7.62x35 mm"],
    "7.5x55 mm Swiss (GP 11)": ["GP 11", "7.5 mm Swiss"],
    "8x57 mm IS": ["8 mm Mauser"],
    ".50 BMG": ["12,7x99 mm NATO"],
}

# Primer per calibre (Boxer sizes of commercial, reloadable brass). Primers sit in the
# centre of the case head. Military surplus can be Berdan-primed with other sizes
# (e.g. 7.62x39, 7.62x54R, 7.5x54 French); rimfire and caseless entries have none.
SMALL_PISTOL, LARGE_PISTOL, SMALL_RIFLE, LARGE_RIFLE, SHOTSHELL_209, BMG_35 = (
    "small-pistol", "large-pistol", "small-rifle", "large-rifle", "shotshell-209", "bmg-35")
PRIMER_DIAMETERS = {  # mm, nominal primer cup diameter
    SMALL_PISTOL: 4.45, SMALL_RIFLE: 4.45,     # .175"
    LARGE_PISTOL: 5.33, LARGE_RIFLE: 5.33,     # .210"
    SHOTSHELL_209: 6.15,                       # .242"
    BMG_35: 8.03,                              # .316", CCI #35
}
PRIMERS = {
    "6.35 mm Browning (.25 ACP)": SMALL_PISTOL, "7.65 mm Browning (.32 ACP)": SMALL_PISTOL,
    "7.65 mm Parabellum": SMALL_PISTOL, ".32 S&W Long": SMALL_PISTOL, ".32 H&R Magnum": SMALL_PISTOL,
    "7.62x25 mm Tokarev": SMALL_PISTOL, "9 mm Browning kurz (.380 ACP)": SMALL_PISTOL,
    "9x18 mm Makarov": SMALL_PISTOL, "9x19 mm": SMALL_PISTOL, "9x21 mm IMI": SMALL_PISTOL,
    ".357 SIG": SMALL_PISTOL, ".38 Special": SMALL_PISTOL, ".357 Magnum": SMALL_PISTOL,
    ".38 Super": SMALL_PISTOL, "10 mm Auto": LARGE_PISTOL, ".40 S&W": SMALL_PISTOL,
    ".41 Magnum": LARGE_PISTOL, ".44 Special": LARGE_PISTOL, ".44 Magnum": LARGE_PISTOL,
    ".45 ACP": LARGE_PISTOL, ".45 Colt": LARGE_PISTOL, ".45 GAP": SMALL_PISTOL,
    ".454 Casull": SMALL_RIFLE, ".460 S&W Magnum": LARGE_RIFLE, ".500 S&W Magnum": LARGE_RIFLE,
    "5.7x28 mm": SMALL_RIFLE, "4.6x30 mm": SMALL_RIFLE,
    ".204 Ruger": SMALL_RIFLE, ".222 Remington": SMALL_RIFLE, ".223 Remington": SMALL_RIFLE,
    "5.56x45 mm NATO": SMALL_RIFLE, "5.6 mm GP 90 (Swiss)": SMALL_RIFLE, ".22-250 Remington": LARGE_RIFLE,
    ".243 Winchester": LARGE_RIFLE, "6 mm BR Norma": SMALL_RIFLE, "6 mm ARC": SMALL_RIFLE,
    "6.5 mm Creedmoor": LARGE_RIFLE, "6.5x55 mm Swedish": LARGE_RIFLE, "6.5x47 mm Lapua": SMALL_RIFLE,
    "6.5 PRC": LARGE_RIFLE, ".260 Remington": LARGE_RIFLE, ".270 Winchester": LARGE_RIFLE,
    "7 mm-08 Remington": LARGE_RIFLE, "7x57 mm Mauser": LARGE_RIFLE, "7x64 mm": LARGE_RIFLE,
    "7 mm Remington Magnum": LARGE_RIFLE, "7 mm PRC": LARGE_RIFLE, "7.5x55 mm Swiss (GP 11)": LARGE_RIFLE,
    "7.5x54 mm French": LARGE_RIFLE, "7.62x39 mm": SMALL_RIFLE, ".300 AAC Blackout": SMALL_RIFLE,
    "7.62x51 mm NATO": LARGE_RIFLE, ".308 Winchester": LARGE_RIFLE, ".30-06 Springfield": LARGE_RIFLE,
    ".30-30 Winchester": LARGE_RIFLE, ".300 Winchester Magnum": LARGE_RIFLE, ".300 PRC": LARGE_RIFLE,
    ".300 Norma Magnum": LARGE_RIFLE, ".303 British": LARGE_RIFLE, "7.62x54 mm R": LARGE_RIFLE,
    "8x57 mm IS": LARGE_RIFLE, "8x68 mm S": LARGE_RIFLE, "9.3x62 mm": LARGE_RIFLE, "9.3x74 mm R": LARGE_RIFLE,
    ".338 Lapua Magnum": LARGE_RIFLE, ".375 H&H Magnum": LARGE_RIFLE, ".416 Rigby": LARGE_RIFLE,
    ".45-70 Government": LARGE_RIFLE, ".50 BMG": BMG_35,
    # Vetterli: the original Swiss service round is rimfire; modern centrefire cases take large rifle.
    "10.4x38 mm R Vetterli": LARGE_RIFLE, ".577 Snider": LARGE_RIFLE, ".577/450 Martini-Henry": LARGE_RIFLE,
    ".50-70 Government": LARGE_RIFLE, ".44-40 WCF": LARGE_PISTOL,
    "12/70": SHOTSHELL_209, "12/76": SHOTSHELL_209, "12/89": SHOTSHELL_209, "16/70": SHOTSHELL_209,
    "20/70": SHOTSHELL_209, "20/76": SHOTSHELL_209, "28/70": SHOTSHELL_209, ".410/76": SHOTSHELL_209,
}
