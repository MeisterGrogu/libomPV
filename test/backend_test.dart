import "../backend/fetcher.dart";

void main() async {
  Vertretungsplan vp = Vertretungsplan(
    schulnummer: 40102573,
    benutzername: "schueler",
    passwort: "AEG_2526_S",
  );

  var tag = await vp.fetch(datum: DateTime(2026, 2, 3));
  var klasse = tag.klasse("9d");

  klasse.stunden().forEach((stunde) {
    if (! stunde.ausfall) {
        print("${stunde.nr} | ${stunde.fach} bei ${stunde.lehrer} in ${stunde.raum}");
    }
  });
}
