from vpmobil import Vertretungsplan
from datetime import date

klasse = "9d"

vp = Vertretungsplan(
    schulnummer=40102573, benutzername="schueler", passwort="AEG_2526_S"
)

tag = vp.fetch(date(2026, 2, 3))
klassen = tag.klassen()

klasse = None

for i in klassen:
    if "9d" in str(i).lower():
        klasse = i

for stunde in klasse.stunden():
    if not stunde.ausfall:
        print(f"{stunde.nr} | {stunde.fach} bei {stunde.lehrer} in {stunde.raum}")
