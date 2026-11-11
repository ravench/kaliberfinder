"""The App Store listing from store/<lang>/*.txt into App Store Connect (.github/workflows/store-listing.yml).

    python3 tools/store_listing.py AuthKey.p8 [--create-version 1.0.0] [--promo-only] [--apply]

Needs ASC_KEY_ID and ASC_ISSUER_ID. Without --apply it only lists what would change.
- Name, subtitle and privacy policy URL go to the app's info (the one not yet live).
- Description, keywords, promotional text and support URL go to the version that is being prepared.
  --create-version makes that version (no build, nothing submitted) when there is none, or renames the
  prepared one to it (a new app comes with «1.0»).
- --promo-only writes just the promotional text, into the live version once there is one (else the prepared one): Apple lets it
  change at any time without review (e.g. to drop «Free at launch» on 1 January).
Never attaches a build and never submits anything for review.
"""
import argparse
import os
import sys

import changelog

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "store")
SITE = "https://ravench.github.io/kaliberfinder/"
# The store's languages: German is the primary one; English for the UK and the US storefronts.
LOCALES = {"de-DE": "de", "en-GB": "en", "en-US": "en", "fr-FR": "fr", "it": "it"}
# Apple's limits, in characters.
LIMITS = {"name": 30, "subtitle": 30, "promotional_text": 170, "keywords": 100, "description": 4000}
INFO_FIELDS = {"name": "name", "subtitle": "subtitle"}
VERSION_FIELDS = {"description": "description", "keywords": "keywords", "promotional_text": "promotionalText"}
# Versions whose texts can still change; READY_FOR_SALE etc. only take a new promotional text.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
LIVE_INFO = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "REPLACED_WITH_NEW_INFO"}


def texts(lang, store=STORE):
    """The listing of one language, from store/<lang>/<field>.txt."""
    out = {}
    for field in LIMITS:
        with open(os.path.join(store, lang, field + ".txt"), encoding="utf-8") as f:
            out[field] = f.read().strip()
    return out


def problems(listing):
    """What App Store Connect would refuse: over-long fields, keywords with spaces around commas."""
    found = [f"{field}: {len(listing[field])} > {limit} characters" for field, limit in LIMITS.items()
             if len(listing[field]) > limit]
    if any(k != k.strip() or not k for k in listing["keywords"].split(",")):
        found.append("keywords: empty or space-padded entry")
    return found


def info_attributes(lang, listing):
    return {**{api: listing[field] for field, api in INFO_FIELDS.items()}, "privacyPolicyUrl": f"{SITE}privacy.html#{lang}"}


def version_attributes(lang, listing, promo_only=False):
    if promo_only:
        return {"promotionalText": listing["promotional_text"]}
    return {**{api: listing[field] for field, api in VERSION_FIELDS.items()}, "supportUrl": f"{SITE}#{lang}"}


def changes(existing, wanted):
    """The attributes of `wanted` that differ from `existing` (an App Store Connect localization or None)."""
    have = (existing or {}).get("attributes", {})
    return {k: v for k, v in wanted.items() if have.get(k) != v}


def requests(kind, parent_kind, parent_id, existing, wanted_by_locale):
    """PATCH or POST requests that bring each locale's localization to `wanted_by_locale`."""
    by_locale = {loc["attributes"]["locale"]: loc for loc in existing}
    out = []
    for locale, wanted in wanted_by_locale.items():
        loc = by_locale.get(locale)
        diff = changes(loc, wanted)
        if not diff:
            continue
        if loc:
            out.append(("PATCH", f"/{kind}/{loc['id']}", {"data": {"type": kind, "id": loc["id"], "attributes": diff}}))
        else:
            relationship = parent_kind[:-1]  # appInfos → appInfo, appStoreVersions → appStoreVersion
            out.append(("POST", f"/{kind}", {"data": {"type": kind, "attributes": {"locale": locale, **wanted},
                                                       "relationships": {relationship: {"data": {"type": parent_kind, "id": parent_id}}}}}))
    return out


def pick_info(infos):
    """The app info that can still change: the one not live, else the only one."""
    open_infos = [i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) not in LIVE_INFO]
    return (open_infos or infos or [None])[0]


def pick_version(versions, promo_only=False):
    """The version being prepared; for --promo-only the live one (READY_FOR_SALE), else the prepared one."""
    def state(v):
        return v["attributes"].get("appVersionState") or v["attributes"].get("appStoreState")
    live = [v for v in versions if state(v) in ("READY_FOR_SALE", "READY_FOR_DISTRIBUTION")]
    editable = [v for v in versions if state(v) in EDITABLE]
    return ((live if promo_only else []) + editable + [None])[0]


def rename(version, wanted):
    """The PATCH that sets the prepared version's number to `wanted` (a new app comes with «1.0»), or None."""
    if not wanted or version is None or version["attributes"].get("versionString") == wanted:
        return None
    return ("PATCH", f"/appStoreVersions/{version['id']}",
            {"data": {"type": "appStoreVersions", "id": version["id"], "attributes": {"versionString": wanted}}})


def describe(method, path, body):
    attributes = body["data"]["attributes"]
    locale = attributes.get("locale", "")
    fields = ", ".join(f"{k} ({len(v)})" if isinstance(v, str) and len(v) > 60 else f"{k}={v!r}"
                       for k, v in attributes.items() if k != "locale")
    return f"{method} {path.split('/')[1]} {locale}: {fields}".replace(" :", ":")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("key")
    parser.add_argument("--create-version")
    parser.add_argument("--promo-only", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv[1:])

    listings = {lang: texts(lang) for lang in sorted(set(LOCALES.values()))}
    bad = [f"{lang} {p}" for lang, listing in listings.items() for p in problems(listing)]
    if bad:
        sys.exit("\n".join(bad))

    key_id, issuer = os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"]

    def call(method, path, body=None):
        return changelog.asc(method, path, changelog.token(args.key, key_id, issuer), body)

    apps = call("GET", f"/apps?filter[bundleId]={changelog.bundle_id()}")["data"]
    if not apps:
        sys.exit("No app on App Store Connect")
    app = apps[0]["id"]
    count = 0

    def run(todo):
        nonlocal count
        for method, path, body in todo:
            print(describe(method, path, body))
            if args.apply:
                call(method, path, body)
        count += len(todo)

    # The version's texts first: adding a language there adds it to the app info too, so the app
    # info's localizations are read only afterwards (else both would POST the same language).
    versions = call("GET", f"/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    version = pick_version(versions, args.promo_only)
    if version is None and args.create_version and not args.promo_only:
        print(f"Create version {args.create_version} (iOS, no build)")
        if args.apply:
            version = call("POST", "/appStoreVersions", {"data": {"type": "appStoreVersions",
                           "attributes": {"platform": "IOS", "versionString": args.create_version},
                           "relationships": {"app": {"data": {"type": "apps", "id": app}}}}})["data"]
    if version is None:
        print("No version to write to: description, keywords, promotional text and support URL wait"
              + ("" if args.apply or not args.create_version else " (dry run: the new version would get them)"))
    else:
        a = version["attributes"]
        print(f"Version {a.get('versionString')} ({a.get('appVersionState') or a.get('appStoreState')})")
        if not args.promo_only:
            run([r for r in [rename(version, args.create_version)] if r])
        existing = call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")["data"]
        wanted = {locale: version_attributes(lang, listings[lang], args.promo_only) for locale, lang in LOCALES.items()}
        run(requests("appStoreVersionLocalizations", "appStoreVersions", version["id"], existing, wanted))

    if not args.promo_only:
        info = pick_info(call("GET", f"/apps/{app}/appInfos")["data"])
        if info is None:
            sys.exit("No app info on App Store Connect")
        existing = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations?limit=50")["data"]
        wanted = {locale: info_attributes(lang, listings[lang]) for locale, lang in LOCALES.items()}
        run(requests("appInfoLocalizations", "appInfos", info["id"], existing, wanted))

    print(f"{count} changes" + ("" if args.apply else " (dry run, nothing written)"))


if __name__ == "__main__":
    main(sys.argv)
