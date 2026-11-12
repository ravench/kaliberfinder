# Release notes

What changed for the people who use the app, written by hand for each release. A release is a
commit on `main` tagged `v<version>` (e.g. `v0.2.0`); pushing the tag uploads it to TestFlight
with that version, and the build takes the section below for that version as its notes, in the
app («Neu in dieser Version») and in TestFlight's «What to Test», instead of the summary the
Claude API writes for ordinary builds. Languages left out fall back to German in the app.

Format: a `## <version>` heading, then `### de`, `### en`, `### fr`, `### it`, each with
`- ` bullets. Newest version first.

## 1.0.0

### de
- Erste Version im App Store. Danke fürs Testen!
- Die Kaliberdaten und die Erkennung entsprechen der letzten TestFlight-Version.

### en
- First version on the App Store. Thank you for testing!
- The calibre data and the recognition are the same as in the last TestFlight build.

### fr
- Première version sur l'App Store. Merci pour vos tests !
- Les données de calibres et la reconnaissance sont celles de la dernière version TestFlight.

### it
- Prima versione sull'App Store. Grazie per i test!
- I dati dei calibri e il riconoscimento sono quelli dell'ultima versione TestFlight.
