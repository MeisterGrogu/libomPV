import 'package:libom_pv/backend/fetcher.dart';

void main() async {
  Vertretungsplan vp = Vertretungsplan(
    schulnummer: 40102573,
    benutzername: "schueler",
    passwort: "AEG_2526_S",
  );

  var tag = await vp.fetch(datum: DateTime.now());
  var klasse = tag.klasse("9d");

  klasse.stunden().forEach((stunde) {
    print("${stunde.nr} | ${!stunde.ausfall ? stunde.fach : "Ausfall"} bei ${!stunde.ausfall ? stunde.lehrer : "niemandem"} in ${!stunde.ausfall ? stunde.raum : "keinem Raum"}");
  });
}
