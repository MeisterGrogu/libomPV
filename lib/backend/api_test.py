from vpmobil import Vertretungsplan
from datetime import date

klasse = "9d"

vp = Vertretungsplan(
    schulnummer=40102573,
    benutzername="schueler",
    passwort="AEG_2526_S",
    serverurl="stundenplan24.de",
    verzeichnis="{schulnummer}/mobil/mobdaten",
    dateinamenschema="PlanKl%Y%m%d.xml",
)

lehrer: set[str] = set()

# list of all teachers in the plan
for tag in range(4, 9):
    tag = vp.fetch(date(2026, 5, tag))

    for klasse in tag.klassen():
        if klasse.kürzel != "GTS":
            for stunde in klasse.stunden():
                if stunde.lehrer:
                    lehrer.add(stunde.lehrer)
                    print(stunde.lehrer + " | " + klasse.kürzel)

print(lehrer)
