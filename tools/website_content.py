"""Texts of the Kaliberfinder website, built by tools/website.py.

The privacy policy must match what the app does: tools/test_privacy_manifest.py
fails when a network API appears, and this policy says the app makes no network
connections. Change both together.
"""

NAME = "Kaliberfinder"
DOMAIN = "kaliberfinder.apps.giotta.ch"
REPO_URL = "https://github.com/ravench/kaliberfinder"
ICON = "Kaliberfinder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# Set to the App Store page once the app is live; until then the site says "coming soon".
STORE_URL = ""
YEAR = 2026
UPDATED = {"de": "4. November 2026", "en": "4 November 2026", "fr": "4 novembre 2026", "it": "4 novembre 2026"}

CONTACT = {
    "email": "",
    "address": [],
    "uid": "CHE-177.370.768",
}

APP = {
    "de": {
        "tagline": "Patronen und Hülsen am Foto erkennen und 1:1 vergleichen.",
        "intro": "Eine Patrone oder Hülse gefunden und das Kaliber ist unklar? Kaliberfinder vergleicht ihre Silhouette "
                 "mit über 200 Kalibern und zeigt die Treffer in Originalgrösse auf dem Display.",
        "features": [
            ("Foto-Erkennung", [
                "Patrone seitlich auf hellem Hintergrund fotografieren oder ein Foto wählen.",
                "Rangliste der wahrscheinlichen Kaliber, auch für leere Hülsen.",
                "Mehrere Patronen im Bild: die gewünschte antippen.",
            ]),
            ("Originalgrösse (1:1)", [
                "Treffer nebeneinander neben einem Millimeter-Lineal, mit Hülsenboden und Zündhütchen.",
                "Patrone aufs Display legen und vergleichen; Kalibrierung mit einer Bankkarte.",
                "LiDAR-Messung von Länge und Durchmesser auf iPhone-Pro-Modellen.",
            ]),
            ("Katalog", [
                "Randfeuer, Kurzwaffen, Langwaffen, Schwarzpulver, Schrot und Luftdruck.",
                "Schweizer Ordonnanzmunition (GP 11, GP 90, GP 1890) und Platzpatronen.",
                "Gemessene Masse eingeben oder Kaliber nach Namen suchen.",
            ]),
        ],
        "note": "Deutsch, Englisch, Französisch und Italienisch. Funktioniert offline, ohne Konto, Tracking oder Werbung. "
                "Die Masse sind gerundete Referenzwerte (CIP/SAAMI) zur Bestimmung, keine Wiederladedaten. "
                "Kaliberfinder verkauft oder bewirbt weder Waffen noch Munition.",
        "privacy": {
            "summary": "Kaliberfinder sammelt keine Daten. Die App baut keine Internetverbindung auf; alles bleibt auf deinem Gerät.",
            "sections": [
                ("Fotos und Kamera", [
                    "Fotos, die du aufnimmst, auswählst oder aus einer anderen App teilst, werden nur auf dem Gerät "
                    "ausgewertet. Sie werden weder gespeichert noch hochgeladen. Ein geteiltes Foto liegt kurz im "
                    "Speicher der App und wird gelöscht, sobald die App es gelesen hat.",
                    "Die Kamera wird nur zum Fotografieren der Patrone verwendet. Die LiDAR-Distanz dient nur der "
                    "Grössenmessung und wird nicht gespeichert. Für die Fotoauswahl braucht die App keinen Zugriff "
                    "auf deine Mediathek.",
                ]),
                ("Einstellungen", [
                    "Masseinheit, Erkennungsmodus, der Schalter für veraltete Kaliber und die Bildschirmkalibrierung "
                    "werden nur auf dem Gerät gespeichert.",
                ]),
                ("Keine Analyse, keine Werbung", [
                    "Die App enthält keine Statistik-, Absturz- oder Werbedienste und keine Software von Dritten, "
                    "die Daten sendet. Es gibt kein Konto.",
                ]),
            ],
        },
        "support_intro": "Antworten auf häufige Fragen. Hilft das nicht weiter, schreib mir.",
        "faq": [
            ("Die Erkennung findet das Kaliber nicht.",
             "Leg die Patrone seitlich auf einen hellen, ruhigen Hintergrund (z. B. weisses Papier), fotografiere "
             "von oben und füll das Bild gut aus. Ohne Massstab sehen sich manche Kaliber sehr ähnlich; vergleiche "
             "dann die Treffer 1:1 auf dem Display oder gib gemessene Masse ein."),
            ("Die 1:1-Ansicht stimmt nicht genau.",
             "Tippe auf dem Startbildschirm unter «Originalgrösse» auf «Bildschirm» und kalibriere mit einer Bankkarte."),
            ("Kann ich die App auf einem anderen Gerät nutzen?",
             "Ein Kauf gilt für alle deine Geräte mit derselben Apple-ID."),
            ("Fehlt ein Kaliber?",
             "Schreib mir das Kaliber mit Massen oder einer Quelle (CIP/SAAMI); ich nehme es gern auf."),
        ],
    },
    "en": {
        "tagline": "Identify cartridges and cases from a photo and compare them at 1:1.",
        "intro": "Found a cartridge or an empty case and don't know the calibre? Kaliberfinder compares its silhouette "
                 "with more than 200 calibres and shows the matches at real size on the screen.",
        "features": [
            ("Photo matching", [
                "Photograph the cartridge lying on its side on a light background, or pick a photo.",
                "A ranked list of likely calibres, empty cases included.",
                "Several cartridges in the photo: tap the one you want.",
            ]),
            ("Real size (1:1)", [
                "Matches side by side next to a millimetre ruler, with the case head and primer.",
                "Lay the cartridge on the screen to compare; calibrate with a bank card.",
                "LiDAR measurement of length and diameter on iPhone Pro models.",
            ]),
            ("Catalogue", [
                "Rimfire, handgun, rifle, black powder, shotgun and air gun calibres.",
                "Swiss service rounds (GP 11, GP 90, GP 1890) and blanks.",
                "Enter measured dimensions or search calibres by name.",
            ]),
        ],
        "note": "English, German, French and Italian. Works offline, with no account, tracking or ads. "
                "Dimensions are rounded reference values (CIP/SAAMI) for identification, not reloading data. "
                "Kaliberfinder does not sell or advertise firearms or ammunition.",
        "privacy": {
            "summary": "Kaliberfinder collects no data. The app makes no internet connections; everything stays on your device.",
            "sections": [
                ("Photos and camera", [
                    "Photos you take, pick or share from another app are analysed on the device only. They are "
                    "neither stored nor uploaded. A shared photo sits briefly in the app's storage and is deleted "
                    "as soon as the app has read it.",
                    "The camera is used only to photograph the cartridge. The LiDAR distance is used only to measure "
                    "size and is not stored. Picking a photo needs no access to your photo library.",
                ]),
                ("Settings", [
                    "The unit, scan mode, obsolete-calibre switch and screen calibration are stored on the device only.",
                ]),
                ("No analytics, no ads", [
                    "The app contains no analytics, crash reporting or advertising services and no third-party "
                    "software that sends data. There is no account.",
                ]),
            ],
        },
        "support_intro": "Answers to common questions. If they don't help, write to me.",
        "faq": [
            ("The photo match doesn't find the calibre.",
             "Lay the cartridge on its side on a light, plain background such as white paper, photograph it from "
             "above and fill the frame. Without a scale some calibres look very much alike; compare the matches "
             "at 1:1 on the screen, or enter measured dimensions."),
            ("The 1:1 view is not exactly right.",
             "On the start screen, tap «Screen» under «Real size» and calibrate it with a bank card."),
            ("Can I use the app on another device?",
             "A purchase covers all your devices with the same Apple ID."),
            ("Is a calibre missing?",
             "Send me the calibre with its dimensions or a source (CIP/SAAMI) and I'll gladly add it."),
        ],
    },
    "fr": {
        "tagline": "Identifier cartouches et douilles sur photo et les comparer en 1:1.",
        "intro": "Vous avez trouvé une cartouche ou une douille et ne connaissez pas le calibre ? Kaliberfinder compare "
                 "sa silhouette avec plus de 200 calibres et affiche les résultats en taille réelle à l'écran.",
        "features": [
            ("Reconnaissance par photo", [
                "Photographiez la cartouche couchée sur un fond clair, ou choisissez une photo.",
                "Une liste classée des calibres probables, douilles vides comprises.",
                "Plusieurs cartouches sur la photo : touchez celle qui vous intéresse.",
            ]),
            ("Taille réelle (1:1)", [
                "Résultats côte à côte à côté d'une règle millimétrée, avec culot et amorce.",
                "Posez la cartouche sur l'écran pour comparer ; calibrage avec une carte bancaire.",
                "Mesure LiDAR de la longueur et du diamètre sur les iPhone Pro.",
            ]),
            ("Catalogue", [
                "Calibres à percussion annulaire, armes de poing, armes d'épaule, poudre noire, chasse et air comprimé.",
                "Munitions d'ordonnance suisses (GP 11, GP 90, GP 1890) et cartouches à blanc.",
                "Saisir des cotes mesurées ou chercher un calibre par son nom.",
            ]),
        ],
        "note": "Français, allemand, anglais et italien. Fonctionne hors ligne, sans compte, suivi ni publicité. "
                "Les cotes sont des valeurs de référence arrondies (CIP/SAAMI) pour l'identification, pas des données "
                "de rechargement. Kaliberfinder ne vend ni ne promeut d'armes ou de munitions.",
        "privacy": {
            "summary": "Kaliberfinder ne collecte aucune donnée. L'app n'établit aucune connexion Internet ; tout reste sur votre appareil.",
            "sections": [
                ("Photos et appareil photo", [
                    "Les photos que vous prenez, choisissez ou partagez depuis une autre app sont analysées uniquement "
                    "sur l'appareil. Elles ne sont ni enregistrées ni envoyées. Une photo partagée reste brièvement "
                    "dans le stockage de l'app et est supprimée dès que l'app l'a lue.",
                    "L'appareil photo sert uniquement à photographier la cartouche. La distance LiDAR sert uniquement "
                    "à mesurer la taille et n'est pas enregistrée. Choisir une photo ne nécessite aucun accès à votre "
                    "photothèque.",
                ]),
                ("Réglages", [
                    "L'unité, le mode de reconnaissance, l'interrupteur des calibres obsolètes et le calibrage de "
                    "l'écran sont enregistrés uniquement sur l'appareil.",
                ]),
                ("Ni statistiques ni publicité", [
                    "L'app ne contient aucun service de statistiques, de rapport de plantage ou de publicité, ni "
                    "logiciel tiers qui envoie des données. Il n'y a pas de compte.",
                ]),
            ],
        },
        "support_intro": "Réponses aux questions fréquentes. Si elles ne suffisent pas, écrivez-moi.",
        "faq": [
            ("La reconnaissance ne trouve pas le calibre.",
             "Posez la cartouche sur le côté sur un fond clair et uni, par exemple du papier blanc, photographiez "
             "d'en haut et remplissez le cadre. Sans échelle, certains calibres se ressemblent beaucoup ; comparez "
             "alors les résultats en 1:1 à l'écran ou saisissez des cotes mesurées."),
            ("La vue 1:1 n'est pas tout à fait juste.",
             "Sur l'écran d'accueil, touchez « Écran » sous « Taille réelle » et calibrez avec une carte bancaire."),
            ("Puis-je utiliser l'app sur un autre appareil ?",
             "Un achat vaut pour tous vos appareils avec le même identifiant Apple."),
            ("Un calibre manque ?",
             "Envoyez-moi le calibre avec ses cotes ou une source (CIP/SAAMI), je l'ajouterai volontiers."),
        ],
    },
    "it": {
        "tagline": "Riconoscere cartucce e bossoli da una foto e confrontarli in 1:1.",
        "intro": "Hai trovato una cartuccia o un bossolo e non conosci il calibro? Kaliberfinder confronta la sua "
                 "sagoma con oltre 200 calibri e mostra i risultati a grandezza reale sullo schermo.",
        "features": [
            ("Riconoscimento da foto", [
                "Fotografa la cartuccia coricata su uno sfondo chiaro, oppure scegli una foto.",
                "Una classifica dei calibri probabili, anche per bossoli vuoti.",
                "Più cartucce nella foto: tocca quella che ti interessa.",
            ]),
            ("Grandezza reale (1:1)", [
                "Risultati affiancati vicino a un righello millimetrato, con fondello e innesco.",
                "Appoggia la cartuccia sullo schermo per confrontare; calibrazione con una carta bancaria.",
                "Misura LiDAR di lunghezza e diametro sugli iPhone Pro.",
            ]),
            ("Catalogo", [
                "Calibri a percussione anulare, armi corte, armi lunghe, polvere nera, a pallini e ad aria compressa.",
                "Munizioni d'ordinanza svizzere (GP 11, GP 90, GP 1890) e cartucce a salve.",
                "Inserire misure rilevate o cercare un calibro per nome.",
            ]),
        ],
        "note": "Italiano, tedesco, francese e inglese. Funziona offline, senza account, tracciamento o pubblicità. "
                "Le misure sono valori di riferimento arrotondati (CIP/SAAMI) per l'identificazione, non dati di "
                "ricarica. Kaliberfinder non vende né promuove armi o munizioni.",
        "privacy": {
            "summary": "Kaliberfinder non raccoglie dati. L'app non si collega a Internet; tutto resta sul tuo dispositivo.",
            "sections": [
                ("Foto e fotocamera", [
                    "Le foto che scatti, scegli o condividi da un'altra app vengono analizzate solo sul dispositivo. "
                    "Non vengono né salvate né caricate. Una foto condivisa resta brevemente nella memoria dell'app "
                    "e viene cancellata non appena l'app l'ha letta.",
                    "La fotocamera serve solo a fotografare la cartuccia. La distanza LiDAR serve solo a misurare la "
                    "grandezza e non viene salvata. Per scegliere una foto l'app non ha bisogno di accedere alla tua "
                    "libreria.",
                ]),
                ("Impostazioni", [
                    "Unità, modalità di riconoscimento, interruttore dei calibri obsoleti e calibrazione dello schermo "
                    "sono salvati solo sul dispositivo.",
                ]),
                ("Niente statistiche, niente pubblicità", [
                    "L'app non contiene servizi di statistica, di segnalazione degli arresti o di pubblicità, né "
                    "software di terzi che invia dati. Non c'è nessun account.",
                ]),
            ],
        },
        "support_intro": "Risposte alle domande frequenti. Se non bastano, scrivimi.",
        "faq": [
            ("Il riconoscimento non trova il calibro.",
             "Appoggia la cartuccia di fianco su uno sfondo chiaro e uniforme, per esempio carta bianca, fotografa "
             "dall'alto e riempi l'inquadratura. Senza scala alcuni calibri si somigliano molto; confronta allora i "
             "risultati in 1:1 sullo schermo o inserisci le misure rilevate."),
            ("La vista 1:1 non è precisa.",
             "Nella schermata iniziale tocca «Schermo» sotto «Grandezza reale» e calibra con una carta bancaria."),
            ("Posso usare l'app su un altro dispositivo?",
             "Un acquisto vale per tutti i tuoi dispositivi con lo stesso ID Apple."),
            ("Manca un calibro?",
             "Mandami il calibro con le misure o una fonte (CIP/SAAMI) e lo aggiungerò volentieri."),
        ],
    },
}
