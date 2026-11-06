#!/usr/bin/env python3
"""Builds the app's website (home, privacy policy, support, imprint) in DE/EN/FR/IT.

The same file lives in ravench/kaliberfinder and ravench/schiesstagebuch; only
tools/website_content.py differs. Keep the two copies identical.

    python3 tools/website.py build _site

German is the default language and sits at the site root; the other languages
live in /en/, /fr/, /it/. Pages are plain static HTML with inline CSS, no
scripts, no cookies and no third-party requests.
"""
import html
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import website_content as content  # noqa: E402

LANGS = ["de", "en", "fr", "it"]
DEFAULT_LANG = "de"
PAGES = ["index", "privacy", "support", "imprint"]

# Words shared by every app's site.
COMMON = {
    "de": {
        "nav": {"index": "Übersicht", "privacy": "Datenschutz", "support": "Support", "imprint": "Impressum"},
        "lang_name": "Deutsch", "soon": "Bald im App Store", "store": "Im App Store laden",
        "contact": "Kontakt", "updated": "Stand", "imprint_owner": "Inhaber",
        "imprint_form": "Rechtsform", "imprint_form_value": "Einzelunternehmen",
        "imprint_uid": "UID", "imprint_email": "E-Mail", "source": "Quellcode",
        "issues": "Fehler melden und Wünsche (GitHub)",
        "web_title": "Diese Website",
        "web_text": "Diese Website setzt keine Cookies, lädt nichts von Dritten und enthält keine Statistik. "
                    "Sie wird von GitHub Pages ausgeliefert; GitHub verarbeitet dabei technisch nötige Daten wie "
                    "die IP-Adresse.",
        "rights_title": "Deine Rechte",
        "rights_text": "Nach dem Schweizer Datenschutzgesetz (DSG) und, wo anwendbar, der DSGVO kannst du Auskunft, "
                       "Berichtigung oder Löschung verlangen. Da die App keine Daten an mich sendet, habe ich keine "
                       "Daten von dir, ausser du schreibst mir eine E-Mail. Schreib dafür an",
        "controller_title": "Verantwortlich",
        "changes_text": "Ändert sich die App so, dass sie Daten anders verwendet, wird diese Seite vorher angepasst.",
        "footer": "© {year} Simon Giotta",
    },
    "en": {
        "nav": {"index": "Overview", "privacy": "Privacy", "support": "Support", "imprint": "Imprint"},
        "lang_name": "English", "soon": "Coming soon to the App Store", "store": "Download on the App Store",
        "contact": "Contact", "updated": "Last updated", "imprint_owner": "Owner",
        "imprint_form": "Legal form", "imprint_form_value": "Sole proprietorship (Einzelunternehmen)",
        "imprint_uid": "Swiss business ID (UID)", "imprint_email": "Email", "source": "Source code",
        "issues": "Report bugs and request features (GitHub)",
        "web_title": "This website",
        "web_text": "This website sets no cookies, loads nothing from third parties and has no analytics. "
                    "It is served by GitHub Pages; GitHub processes technically necessary data such as your "
                    "IP address.",
        "rights_title": "Your rights",
        "rights_text": "Under the Swiss Federal Act on Data Protection (FADP) and, where it applies, the GDPR you can "
                       "ask for access, correction or deletion. As the app sends no data to me, I hold no data about "
                       "you unless you email me. To ask, write to",
        "controller_title": "Controller",
        "changes_text": "If the app ever starts using data differently, this page will be updated first.",
        "footer": "© {year} Simon Giotta",
    },
    "fr": {
        "nav": {"index": "Aperçu", "privacy": "Confidentialité", "support": "Assistance", "imprint": "Mentions légales"},
        "lang_name": "Français", "soon": "Bientôt sur l'App Store", "store": "Télécharger dans l'App Store",
        "contact": "Contact", "updated": "Mise à jour", "imprint_owner": "Titulaire",
        "imprint_form": "Forme juridique", "imprint_form_value": "Entreprise individuelle",
        "imprint_uid": "IDE", "imprint_email": "E-mail", "source": "Code source",
        "issues": "Signaler un bug ou proposer une idée (GitHub)",
        "web_title": "Ce site web",
        "web_text": "Ce site ne dépose aucun cookie, ne charge rien de tiers et ne contient aucune statistique. "
                    "Il est servi par GitHub Pages ; GitHub traite les données techniquement nécessaires comme "
                    "l'adresse IP.",
        "rights_title": "Vos droits",
        "rights_text": "Selon la loi suisse sur la protection des données (LPD) et, le cas échéant, le RGPD, vous pouvez "
                       "demander l'accès, la rectification ou l'effacement. L'app ne m'envoyant aucune donnée, je ne "
                       "détiens aucune donnée sur vous, sauf si vous m'écrivez un e-mail. Pour toute demande :",
        "controller_title": "Responsable",
        "changes_text": "Si l'app devait un jour utiliser les données autrement, cette page serait mise à jour avant.",
        "footer": "© {year} Simon Giotta",
    },
    "it": {
        "nav": {"index": "Panoramica", "privacy": "Privacy", "support": "Assistenza", "imprint": "Note legali"},
        "lang_name": "Italiano", "soon": "Presto nell'App Store", "store": "Scarica dall'App Store",
        "contact": "Contatto", "updated": "Aggiornato", "imprint_owner": "Titolare",
        "imprint_form": "Forma giuridica", "imprint_form_value": "Ditta individuale",
        "imprint_uid": "IDI", "imprint_email": "E-mail", "source": "Codice sorgente",
        "issues": "Segnala errori e proponi idee (GitHub)",
        "web_title": "Questo sito",
        "web_text": "Questo sito non usa cookie, non carica nulla da terzi e non contiene statistiche. "
                    "È servito da GitHub Pages; GitHub tratta i dati tecnicamente necessari come l'indirizzo IP.",
        "rights_title": "I tuoi diritti",
        "rights_text": "In base alla legge svizzera sulla protezione dei dati (LPD) e, se applicabile, al GDPR puoi "
                       "chiedere accesso, rettifica o cancellazione. Poiché l'app non mi invia dati, non ho dati su di te, "
                       "salvo se mi scrivi un'e-mail. Per richieste scrivi a",
        "controller_title": "Titolare del trattamento",
        "changes_text": "Se l'app dovesse usare i dati in modo diverso, questa pagina verrà aggiornata prima.",
        "footer": "© {year} Simon Giotta",
    },
}

CURRENT_PAGE = ' aria-current="page"'
CURRENT_LANG = ' aria-current="true"'
GITHUB_PRIVACY = "https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement"

CSS = """
:root { --bg: #F1E6D2; --card: #FBF6EC; --text: #1F2533; --muted: #5C6372; --accent: #2B3A55; --line: #DCC9A8; }
@media (prefers-color-scheme: dark) {
  :root { --bg: #18233A; --card: #22304B; --text: #EEF1F6; --muted: #AEB6C6; --accent: #DCC9A8; --line: #33415E; }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 17px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
a { color: var(--accent); }
header, main, footer { max-width: 760px; margin: 0 auto; padding: 0 16px; }
header { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; padding-top: 20px; }
header .brand { display: flex; align-items: center; gap: 10px; font-weight: 600; text-decoration: none; color: var(--text); margin-right: auto; }
header .brand img { width: 40px; height: 40px; border-radius: 9px; }
nav { display: flex; flex-wrap: wrap; gap: 6px 14px; font-size: 15px; }
nav a { text-decoration: none; }
nav a[aria-current="page"] { font-weight: 600; text-decoration: underline; }
.langs { width: 100%; font-size: 14px; color: var(--muted); display: flex; gap: 10px; }
.langs a[aria-current="true"] { font-weight: 600; color: var(--text); text-decoration: none; }
main { padding-top: 12px; padding-bottom: 32px; }
.hero { display: flex; gap: 20px; align-items: center; margin: 24px 0; }
.hero img { width: 112px; height: 112px; border-radius: 25px; flex: none; box-shadow: 0 2px 10px rgba(0,0,0,.15); }
.hero h1 { margin: 0 0 6px; font-size: 30px; line-height: 1.2; }
.hero p { margin: 0; color: var(--muted); }
.badge { display: inline-block; margin-top: 10px; padding: 6px 12px; border-radius: 999px; background: var(--accent); color: var(--bg); font-size: 14px; font-weight: 600; text-decoration: none; }
section { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 4px 20px 12px; margin: 16px 0; }
h2 { font-size: 20px; margin: 16px 0 6px; }
ul { padding-left: 20px; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 4px 16px; }
dt { color: var(--muted); }
dd { margin: 0; }
footer { color: var(--muted); font-size: 14px; padding-bottom: 32px; }
@media (max-width: 520px) { .hero { flex-direction: column; align-items: flex-start; } dl { grid-template-columns: 1fr; } dd { margin-bottom: 8px; } }
"""


def esc(text):
    return html.escape(text, quote=True)


def page_path(lang, page):
    """Path of a page relative to the site root."""
    prefix = "" if lang == DEFAULT_LANG else f"{lang}/"
    return f"{prefix}{'index' if page == 'index' else page}.html"


def rel_link(from_lang, lang, page):
    """Relative link from any page of from_lang to page in lang."""
    up = "" if from_lang == DEFAULT_LANG else "../"
    return up + page_path(lang, page)


def check_config():
    """The contact details must be filled in before the site can be built."""
    missing = [key for key in ("email", "address") if not content.CONTACT.get(key)]
    if missing:
        raise SystemExit(f"tools/website_content.py: CONTACT is missing {', '.join(missing)}")


def mail_link():
    email = content.CONTACT["email"]
    return f'<a href="mailto:{esc(email)}">{esc(email)}</a>'


def address_html():
    return "<br>".join(esc(line) for line in content.CONTACT["address"])


def render_index(lang):
    app = content.APP[lang]
    c = COMMON[lang]
    store = content.STORE_URL
    badge = (f'<a class="badge" href="{esc(store)}">{esc(c["store"])}</a>' if store
             else f'<span class="badge">{esc(c["soon"])}</span>')
    parts = [f'<div class="hero"><img src="{"" if lang == DEFAULT_LANG else "../"}icon.png" alt="">'
             f'<div><h1>{esc(content.NAME)}</h1><p>{esc(app["tagline"])}</p>{badge}</div></div>',
             f'<p>{esc(app["intro"])}</p>']
    for title, items in app["features"]:
        parts.append(f"<section><h2>{esc(title)}</h2><ul>"
                     + "".join(f"<li>{esc(item)}</li>" for item in items) + "</ul></section>")
    parts.append(f'<p>{esc(app["note"])}</p>')
    return app["tagline"], "\n".join(parts)


def render_privacy(lang):
    app = content.APP[lang]
    c = COMMON[lang]
    p = app["privacy"]
    parts = [f"<h1>{esc(c['nav']['privacy'])}</h1>",
             f"<p><strong>{esc(p['summary'])}</strong></p>"]
    for title, paragraphs in p["sections"]:
        parts.append(f"<section><h2>{esc(title)}</h2>" + "".join(f"<p>{esc(t)}</p>" for t in paragraphs) + "</section>")
    parts.append(f"<section><h2>{esc(c['web_title'])}</h2><p>{esc(c['web_text'])} "
                 f'(<a href="{GITHUB_PRIVACY}">GitHub Privacy Statement</a>)</p></section>')
    parts.append(f"<section><h2>{esc(c['rights_title'])}</h2><p>{esc(c['rights_text'])} {mail_link()}.</p>"
                 f"<p>{esc(c['changes_text'])}</p></section>")
    parts.append(f"<section><h2>{esc(c['controller_title'])}</h2><p>{address_html()}<br>{mail_link()}</p></section>")
    parts.append(f"<p>{esc(c['updated'])}: {esc(content.UPDATED[lang])}</p>")
    return c["nav"]["privacy"], "\n".join(parts)


def render_support(lang):
    app = content.APP[lang]
    c = COMMON[lang]
    parts = [f"<h1>{esc(c['nav']['support'])}</h1>", f"<p>{esc(app['support_intro'])}</p>"]
    for question, answer in app["faq"]:
        parts.append(f"<section><h2>{esc(question)}</h2><p>{esc(answer)}</p></section>")
    parts.append(f"<section><h2>{esc(c['contact'])}</h2><p>{mail_link()}</p>"
                 f'<p><a href="{esc(content.REPO_URL)}/issues">{esc(c["issues"])}</a><br>'
                 f'<a href="{esc(content.REPO_URL)}">{esc(c["source"])}</a></p></section>')
    return c["nav"]["support"], "\n".join(parts)


def render_imprint(lang):
    c = COMMON[lang]
    rows = [(c["imprint_owner"], address_html()),
            (c["imprint_form"], esc(c["imprint_form_value"])),
            (c["imprint_uid"], esc(content.CONTACT["uid"])),
            (c["imprint_email"], mail_link())]
    body = "".join(f"<dt>{esc(k)}</dt><dd>{v}</dd>" for k, v in rows)
    return c["nav"]["imprint"], f"<h1>{esc(c['nav']['imprint'])}</h1><section><dl>{body}</dl></section>"


RENDERERS = {"index": render_index, "privacy": render_privacy, "support": render_support, "imprint": render_imprint}


def render(lang, page):
    c = COMMON[lang]
    title, body = RENDERERS[page](lang)
    full_title = content.NAME if page == "index" else f"{title} · {content.NAME}"
    up = "" if lang == DEFAULT_LANG else "../"
    nav = "".join(
        f'<a href="{rel_link(lang, lang, p)}"{CURRENT_PAGE if p == page else ""}>{esc(c["nav"][p])}</a>'
        for p in PAGES)
    langs = "".join(
        f'<a href="{rel_link(lang, other, page)}" hreflang="{other}"{CURRENT_LANG if other == lang else ""}>'
        f'{esc(COMMON[other]["lang_name"])}</a>'
        for other in LANGS)
    alternates = "".join(
        f'<link rel="alternate" hreflang="{other}" href="https://{content.DOMAIN}/{page_path(other, page)}">'
        for other in LANGS)
    description = content.APP[lang]["tagline"]
    return f"""<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(full_title)}</title>
<meta name="description" content="{esc(description)}">
<link rel="icon" href="{up}icon.png">
<link rel="apple-touch-icon" href="{up}icon.png">
{alternates}
<style>{CSS}</style>
</head>
<body>
<header>
<a class="brand" href="{rel_link(lang, lang, 'index')}"><img src="{up}icon.png" alt="">{esc(content.NAME)}</a>
<nav>{nav}</nav>
<div class="langs">{langs}</div>
</header>
<main>
{body}
</main>
<footer>{esc(c["footer"].format(year=content.YEAR))} · <a href="{rel_link(lang, lang, 'imprint')}">{esc(c["nav"]["imprint"])}</a></footer>
</body>
</html>
"""


def build(out):
    check_config()
    out = Path(out)
    if out.exists():
        shutil.rmtree(out)
    for lang in LANGS:
        for page in PAGES:
            target = out / page_path(lang, page)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(render(lang, page), encoding="utf-8")
    icon = (ROOT / content.ICON).read_bytes()
    if not icon.startswith(b"\x89PNG"):
        # A Git LFS pointer instead of the image: the checkout ran without LFS.
        raise SystemExit(f"{content.ICON} is not a PNG; fetch it with `git lfs pull`")
    (out / "icon.png").write_bytes(icon)
    (out / "CNAME").write_text(content.DOMAIN + "\n", encoding="utf-8")
    # GitHub Pages: serve files as they are.
    (out / ".nojekyll").write_text("", encoding="utf-8")
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "build":
        raise SystemExit("usage: python3 tools/website.py build <output directory>")
    print(f"Built {build(sys.argv[2])}")
