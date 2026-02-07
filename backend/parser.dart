// Required dependencies in pubspec.yaml:
// dependencies:
//   xml: ^6.6.1

import 'package:xml/xml.dart';
import 'dart:io';
import 'dart:convert';

// exceptions.dart - Custom exception classes
class Exceptions {
  static XMLNotFoundException XMLNotFound(String message) {
    return XMLNotFoundException(message);
  }
}

class XMLNotFoundException implements Exception {
  final String message;
  
  XMLNotFoundException(this.message);
  
  @override
  String toString() => 'XMLNotFoundException: $message';
}

// lib.dart - Pretty XML utility function
String prettyxml(XmlDocument document) {
  return document.toXmlString(pretty: true, indent: '  ');
}

// Main VpDay class
class VpDay {
  late XmlDocument _mobdaten;
  late XmlElement _dataroot;
  late DateTime zeitstempel;
  late String datei;
  late DateTime datum;
  late int wochentag;
  late String zusatzInfo;

  VpDay(dynamic mobdaten) {
    // Handle different input types: XmlDocument, bytes (List<int>), or String
    if (mobdaten is XmlDocument) {
      _mobdaten = mobdaten;
    } else if (mobdaten is List<int>) {
      // Convert bytes to string and parse
      final xmlString = String.fromCharCodes(mobdaten);
      _mobdaten = XmlDocument.parse(xmlString);
    } else if (mobdaten is String) {
      _mobdaten = XmlDocument.parse(mobdaten);
    } else {
      throw ArgumentError('mobdaten must be XmlDocument, List<int>, or String');
    }

    _dataroot = _mobdaten.rootElement;

    // Parse zeitstempel
    final zeitstempelText = _mobdaten.findAllElements('Kopf').first
        .findElements('zeitstempel').first.innerText;
    zeitstempel = _parseDateTime(zeitstempelText, '%d.%m.%Y, %H:%M');

    // Get datei
    datei = _mobdaten.findAllElements('Kopf').first
        .findElements('datei').first.innerText;

    // Parse datum from datei string (characters 6-14)
    datum = _parseDate(datei.substring(6, 14), '%Y%m%d');

    // Get weekday (0 = Monday in Dart, 1 = Monday in Python)
    // Dart's DateTime.weekday: 1 = Monday, 7 = Sunday
    // Python's weekday(): 0 = Monday, 6 = Sunday
    wochentag = datum.weekday - 1;

    // Build zusatzInfo from ZiZeile elements
    List<String> ziZeilen = [];
    for (var zusatzInfo in _dataroot.findAllElements('ZusatzInfo')) {
      for (var ziZeile in zusatzInfo.findElements('ZiZeile')) {
        final text = ziZeile.innerText;
        if (text.isNotEmpty) {
          ziZeilen.add(text);
        }
      }
    }
    zusatzInfo = ziZeilen.join('\n');
  }

  // Helper method to parse datetime string with format
  DateTime _parseDateTime(String dateStr, String format) {
    // Convert Python strptime format to Dart parsing
    // Python: "%d.%m.%Y, %H:%M" -> "31.12.2023, 14:30"
    final parts = dateStr.split(', ');
    final dateParts = parts[0].split('.');
    final timeParts = parts[1].split(':');
    
    return DateTime(
      int.parse(dateParts[2]), // year
      int.parse(dateParts[1]), // month
      int.parse(dateParts[0]), // day
      int.parse(timeParts[0]), // hour
      int.parse(timeParts[1]), // minute
    );
  }

  // Helper method to parse date string with format
  DateTime _parseDate(String dateStr, String format) {
    // Convert Python strptime format to Dart parsing
    // Python: "%Y%m%d" -> "20231231"
    final year = int.parse(dateStr.substring(0, 4));
    final month = int.parse(dateStr.substring(4, 6));
    final day = int.parse(dateStr.substring(6, 8));
    
    return DateTime(year, month, day);
  }

  @override
  String toString() {
    final formattedDate = '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}';
    return 'Vertretungsplan vom $formattedDate';
  }

  List<Klasse> klassen() {
    List<Klasse> klassen = [];
    final klassenElemente = _dataroot.findAllElements('Kl');
    
    if (klassenElemente.isNotEmpty) {
      for (var kl in klassenElemente) {
        final kurz = kl.findElements('Kurz');
        if (kurz.isNotEmpty) {
          klassen.add(Klasse(xmldata: kl));
        }
      }
      return klassen;
    }
    throw Exceptions.XMLNotFound('Keine Klassen gefunden');
  }

  Klasse klasse(String kuerzel) {
    final klassenList = klassen();
    for (var kl in klassenList) {
      if (kl.kuerzel == kuerzel) {
        return kl;
      }
    }
    throw Exceptions.XMLNotFound('Keine Klasse $kuerzel gefunden');
  }

  List<DateTime> freieTage() {
    final freieTageElement = _dataroot.findElements('FreieTage');
    if (freieTageElement.isEmpty) {
      throw Exceptions.XMLNotFound(
          "Element 'FreieTage' nicht in den XML-Daten gefunden");
    }

    List<DateTime> freieTageList = [];
    for (var ft in freieTageElement.first.findElements('ft')) {
      final text = ft.innerText;
      if (text.isNotEmpty) {
        // Parse format "%y%m%d" -> "231231"
        final year = 2000 + int.parse(text.substring(0, 2));
        final month = int.parse(text.substring(2, 4));
        final day = int.parse(text.substring(4, 6));
        freieTageList.add(DateTime(year, month, day));
      }
    }
    return freieTageList;
  }

  List<String> lehrerKrank() {
    List<String> leKrank = [];
    List<String> leNichtKrank = [];

    final klassenElement = _dataroot.findElements('Klassen');
    if (klassenElement.isEmpty) {
      return [];
    }

    for (var kl in klassenElement.first.findElements('Kl')) {
      List<Map<String, String>> lehrerInfo = [];
      
      final unterrichtElement = kl.findElements('Unterricht');
      if (unterrichtElement.isEmpty) {
        continue;
      }

      // Wir sammeln fuer alle Kurse dieser Klasse die Nummer und das Lehrerkuerzel
      for (var ue in unterrichtElement.first.findElements('Ue')) {
        final ueNrElement = ue.findElements('UeNr');
        if (ueNrElement.isNotEmpty) {
          final nr = ueNrElement.first.innerText;
          final kurz = ueNrElement.first.getAttribute('UeLe') ?? '';
          lehrerInfo.add({'nr': nr, 'kurz': kurz});
        }
      }

      List<Stunde> alleStd;
      try {
        alleStd = Klasse(xmldata: kl).stunden();
      } catch (e) {
        continue;
      }

      // Jetzt gehen wir durch alle Stunden und schauen, ob sie geändert sind
      for (var std in alleStd) {
        // Wenn nicht fuegen wir die Lehrer, welche die Stunde halten zu den nicht kranken Lehrern hinzu
        if (!std.anders && !std.ausfall && !std.besonders) {
          for (var sr in std.lehrer.split(' ')) {
            if (sr.isNotEmpty) {
              leNichtKrank.add(sr);
              // Wenn der Lehrer fälschlicherweise als krank eingeordnet wurde, löschen wir ihn aus der kranken Liste
              if (leKrank.contains(sr)) {
                leKrank.remove(sr);
              }
            }
          }
        } else if (std.anders && !std.ausfall && !std.besonders) {
          for (var sr in std.lehrer.split(' ')) {
            if (sr.isNotEmpty) {
              leNichtKrank.add(sr);
              // Wenn der Lehrer fälschlicherweise als krank eingeordnet wurde, löschen wir ihn aus der kranken Liste
              if (leKrank.contains(sr)) {
                leKrank.remove(sr);
              }
            }
          }
        } else if (std.anders && std.ausfall && !std.besonders) {
          try {
            final le = lehrerInfo.firstWhere(
              (item) => item['nr'] == std.kursnummer.toString()
            );
            // Wenn die Stunde geändert ist schauen wir, ob der lehrer schon in der nicht kranken Liste ist.
            if (!leNichtKrank.contains(le['kurz'])) {
              // Wenn nicht, muss er krank sein
              if (!leKrank.contains(le['kurz'])) {
                leKrank.add(le['kurz']!);
              }
            }
          } catch (e) {
            // No matching item found, continue
            continue;
          }
        } else if (std.besonders) {
          try {
            final splitLe = std.lehrer.split(' ');
            for (var sr in splitLe) {
              if (sr.isNotEmpty) {
                leNichtKrank.add(sr);
              }
            }
          } catch (e) {
            continue;
          }
        }
      }
    }

    // Sorry fuer den mess, aber es funktioniert und fast alles ist leider auch nötig
    leKrank.sort();
    return leKrank;
  }

  void saveasfile({String pfad = './datei.xml', bool overwrite = false}) {
    final xmlpretty = prettyxml(_mobdaten);

    final zielpfad = File(pfad).absolute.path;
    final directory = File(zielpfad).parent.path;

    // Stellt sicher, dass das Verzeichnis existiert
    if (!Directory(directory).existsSync()) {
      Directory(directory).createSync(recursive: true);
    }

    if (File(zielpfad).existsSync() && !overwrite) {
      throw FileSystemException('Die Datei $zielpfad existiert bereits.');
    }

    File(zielpfad).writeAsStringSync(xmlpretty, encoding: utf8);
  }
}

class Klasse {
  late XmlElement _data;
  late String kuerzel;

  Klasse({required XmlElement xmldata}) {
    _data = xmldata;
    // Kuerzel der Klasse
    kuerzel = _data.findElements('Kurz').first.innerText;
  }

  @override
  String toString() {
    return 'Vertretungsplan der Klasse $kuerzel';
  }

  List<Stunde> stundenInPeriode(int periode) {
    List<Stunde> fin = [];
    final plElements = _data.findElements('Pl');
    
    if (plElements.isEmpty) {
      throw Exceptions.XMLNotFound(
          'Keine Stunden zu dieser Stundenplanperiode gefunden!');
    }

    final pl = plElements.first;
    for (var std in pl.findElements('Std')) {
      final stElements = std.findElements('St');
      if (stElements.isNotEmpty && stElements.first.innerText == periode.toString()) {
        fin.add(Stunde(xmldata: std));
      }
    }

    if (fin.isNotEmpty) {
      return fin;
    } else {
      throw Exceptions.XMLNotFound(
          'Keine Stunden zu dieser Stundenplanperiode gefunden!');
    }
  }

  List<Stunde> stunden() {
    List<Stunde> fin = [];
    final plElements = _data.findElements('Pl');
    
    if (plElements.isEmpty) {
      throw Exceptions.XMLNotFound('Keine Stunden fuer diese Klasse gefunden!');
    }

    final pl = plElements.first;
    for (var std in pl.findElements('Std')) {
      final stElements = std.findElements('St');
      if (stElements.isNotEmpty) {
        fin.add(Stunde(xmldata: std));
      }
    }

    if (fin.isNotEmpty) {
      return fin;
    } else {
      throw Exceptions.XMLNotFound('Keine Stunden fuer diese Klasse gefunden!');
    }
  }

  List<Kurs> kurseInPeriode(int periode) {
    final stdList = stundenInPeriode(periode);
    List<Kurs> fin = [];
    List<Kurs> alleKurse = [];

    final unterrichtElements = _data.findElements('Unterricht');
    if (unterrichtElements.isEmpty) {
      throw Exceptions.XMLNotFound('Keinen passenden Kurs gefunden!');
    }

    for (var elemn in unterrichtElements.first.findElements('Ue')) {
      alleKurse.add(Kurs(elemn));
    }

    for (var elem in stdList) {
      try {
        final matchingKurs = alleKurse.firstWhere(
          (x) => x.kursnummer == elem.kursnummer.toString()
        );
        fin.add(matchingKurs);
      } catch (e) {
        throw Exceptions.XMLNotFound('Keinen passenden Kurs gefunden!');
      }
    }
    return fin;
  }

  List<Kurs> alleKurse() {
    List<Kurs> fin = [];
    final unterrichtElements = _data.findElements('Unterricht');
    
    if (unterrichtElements.isEmpty) {
      return fin;
    }

    for (var elem in unterrichtElements.first.findElements('Ue')) {
      fin.add(Kurs(elem));
    }
    return fin;
  }

  List<Kurs> alleKurseHeute() {
    final alleKurseList = alleKurse();
    final stdHeut = stunden();
    List<Kurs> fin = [];

    for (var elem in stdHeut) {
      try {
        final matchingKurs = alleKurseList.firstWhere(
          (x) => x.kursnummer == elem.kursnummer.toString()
        );
        fin.add(matchingKurs);
      } catch (e) {
        throw Exceptions.XMLNotFound('Keine passenden Kurse gefunden!');
      }
    }
    return fin;
  }
}

class Stunde {
  late XmlElement _data;
  late int nr;
  late String beginn;
  late String ende;
  late bool anders;
  late bool ausfall;
  late bool besonders;
  late int kursnummer;
  late String fach;
  late String lehrer;
  late String raum;
  late String info;

  Stunde({required dynamic xmldata}) {
    // Handle different input types: XmlElement, bytes (List<int>), or String
    if (xmldata is XmlElement) {
      _data = xmldata;
    } else if (xmldata is List<int>) {
      // Convert bytes to string and parse
      final xmlString = String.fromCharCodes(xmldata);
      _data = XmlDocument.parse(xmlString).rootElement;
    } else if (xmldata is String) {
      _data = XmlDocument.parse(xmldata).rootElement;
    } else {
      throw ArgumentError('xmldata must be XmlElement, List<int>, or String');
    }

    nr = int.parse(_data.findElements('St').first.innerText);

    beginn = _data.findElements('Beginn').first.innerText;

    ende = _data.findElements('Ende').first.innerText;

    final faElement = _data.findElements('Fa').first;
    final raElement = _data.findElements('Ra').first;
    final leElement = _data.findElements('Le').first;

    if (faElement.getAttribute('FaAe') != null ||
        raElement.getAttribute('RaAe') != null ||
        leElement.getAttribute('LeAe') != null) {
      anders = true;
    } else {
      anders = false;
    }

    if (faElement.innerText == '---') {
      ausfall = true;
    } else {
      ausfall = false;
    }

    besonders = false;
    try {
      final nrElements = _data.findElements('Nr');
      if (nrElements.isNotEmpty) {
        kursnummer = int.parse(nrElements.first.innerText);
      } else {
        besonders = true;
        kursnummer = -1;
      }
    } catch (e) {
      besonders = true;
      kursnummer = -1;
    }

    String fachTemp;
    final faElements = _data.findElements('Fa');
    if (faElements.isNotEmpty && faElements.first.innerText.isNotEmpty) {
      fachTemp = faElements.first.innerText;
    } else {
      fachTemp = '';
    }
    fach = (!ausfall && !besonders) ? fachTemp : '';

    String tmpLe;
    final leElements = _data.findElements('Le');
    if (leElements.isNotEmpty && leElements.first.innerText.isNotEmpty) {
      tmpLe = leElements.first.innerText;
    } else {
      tmpLe = '';
    }
    lehrer = !ausfall ? tmpLe : '';

    String tmpRa;
    final raElements = _data.findElements('Ra');
    if (raElements.isNotEmpty && raElements.first.innerText.isNotEmpty) {
      tmpRa = raElements.first.innerText;
    } else {
      tmpRa = '';
    }
    raum = !ausfall ? tmpRa : '';

    final ifElements = _data.findElements('If');
    info = ifElements.isNotEmpty ? ifElements.first.innerText : '';
  }

  @override
  String toString() {
    return 'Stundenobjekt der $nr. Stunde bei $lehrer';
  }
}

// ╭──────────────────────────────────────────────────────────────────────────────────────────╮
// │                                         Kurs                                             │
// ╰──────────────────────────────────────────────────────────────────────────────────────────╯

class Kurs {
  late XmlElement _data;
  late String lehrer;
  late String fach;
  late String zusatz;
  late String kursnummer;

  Kurs(dynamic xmldata) {
    XmlElement tempData;
    
    // Handle different input types: XmlElement, bytes (List<int>), or String
    if (xmldata is XmlElement) {
      tempData = xmldata;
    } else if (xmldata is List<int>) {
      // Convert bytes to string and parse
      final xmlString = String.fromCharCodes(xmldata);
      tempData = XmlDocument.parse(xmlString).rootElement;
    } else if (xmldata is String) {
      tempData = XmlDocument.parse(xmldata).rootElement;
    } else {
      throw ArgumentError('xmldata must be XmlElement, List<int>, or String');
    }

    // Ich nehme direkt das UeNr-Element, da das Ue Element nichts brauchbares enthält
    final ueNrElements = tempData.findElements('UeNr');
    if (ueNrElements.isNotEmpty) {
      _data = ueNrElements.first;
    } else {
      throw Exceptions.XMLNotFound('UeNr element not found');
    }

    lehrer = _data.getAttribute('UeLe') ?? '';

    fach = _data.getAttribute('UeFa') ?? '';

    zusatz = _data.getAttribute('UeGr') ?? '';

    kursnummer = _data.innerText;
  }
}
