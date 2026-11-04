"""Extra spellings found on headstamps (the stamp on the case base), so the
catalogue search finds a calibre by what is written on the case. Kept apart from cartridges.py so that file
stays an exact copy of the Schiesstagebuch catalogue.

Matching ignores case, spaces, dots and "mm", so "9MM LUGER", "9 mm Luger"
and "9mmluger" are the same. Names and aliases from cartridges.py are matched
too; list only spellings that aren't already covered there.
"""

HEADSTAMPS = {
    ".22 WMR": ["22 WIN MAG", "22 WMR"],
    ".17 HMR": ["17 HMR"],
    "6.35 mm Browning (.25 ACP)": ["25 AUTO", "6,35"],
    "7.65 mm Browning (.32 ACP)": ["32 AUTO", "7,65"],
    "7.62x25 mm Tokarev": ["7.62x25"],
    "9 mm Browning kurz (.380 ACP)": ["380 AUTO", "9mm K", "9 KURZ"],
    "9x18 mm Makarov": ["9x18", "9mm MAK"],
    "9x19 mm": ["9mm LUGER", "9 LUGER", "9mm PARA", "9x19 PARA", "9mm NATO"],
    ".357 SIG": ["357 SIG"],
    ".38 Special": ["38 SPL", "38 SPECIAL", "38 SPL +P"],
    ".357 Magnum": ["357 MAG", "357 MAGNUM", "357 REM MAG"],
    ".38 Super": ["38 SUPER AUTO", "38 SUPER"],
    "10 mm Auto": ["10mm AUTO"],
    ".40 S&W": ["40 S&W", "40 SW", "40 S+W"],
    ".44 Special": ["44 SPL", "44 S&W SPL"],
    ".44 Magnum": ["44 MAG", "44 REM MAG", "44 REM MAGNUM"],
    ".45 ACP": ["45 AUTO", "45 ACP"],
    ".45 Colt": ["45 COLT", "45 LC"],
    "5.7x28 mm": ["FN 5.7x28"],
    ".223 Remington": ["223 REM", "REM 223", "223 REMINGTON"],
    "5.56x45 mm NATO": ["5.56", "5.56x45"],
    ".22-250 Remington": ["22-250 REM", "22-250"],
    ".243 Winchester": ["243 WIN", "WIN 243"],
    "6.5 mm Creedmoor": ["6.5 CREEDMOOR", "6.5 CM"],
    "6.5x55 mm Swedish": ["6.5x55 SE", "6,5x55"],
    ".270 Winchester": ["270 WIN", "WIN 270"],
    "7 mm-08 Remington": ["7mm-08 REM"],
    "7x64 mm": ["7x64"],
    "7 mm Remington Magnum": ["7mm REM MAG"],
    "7.62x39 mm": ["7.62x39"],
    ".300 AAC Blackout": ["300 BLK", "300 AAC BLACKOUT"],
    "7.62x51 mm NATO": ["7.62x51", "7.62 NATO"],
    ".308 Winchester": ["308 WIN", "WIN 308", "308 WINCHESTER"],
    ".30-06 Springfield": ["30-06 SPRG", "30-06 SPFLD", "30-06"],
    ".30-30 Winchester": ["30-30 WIN", "30 WCF"],
    ".300 Winchester Magnum": ["300 WIN MAG", "300 WM"],
    ".303 British": ["303 BRIT", ".303"],
    "7.62x54 mm R": ["7.62x54R"],
    "8x57 mm IS": ["8x57 JS", "8x57 IS", "8mm MAUSER"],
    "9.3x62 mm": ["9,3x62"],
    ".338 Lapua Magnum": ["338 LAPUA MAG", "338 LAPUA"],
    ".375 H&H Magnum": ["375 H&H MAG", "375 H&H"],
    ".45-70 Government": ["45-70 GOVT", "45-70"],
    ".50 BMG": ["50 BMG"],
}
