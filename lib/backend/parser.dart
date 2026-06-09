import 'package:xml/xml.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

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

String prettyxml(XmlDocument document) {
  return document.toXmlString(pretty: true, indent: '  ');
}

class VpDay {
  late XmlDocument _mobdaten;
  late XmlElement _dataroot;
  late DateTime zeitstempel;
  late String datei;
  late DateTime datum;
  late int wochentag;
  late String zusatzInfo;
  late bool regulaerPlan = false;
  late String woche;

  VpDay(dynamic mobdaten, [DateTime? datumP]) {
    // Handle different input types: XmlDocument, bytes (List<int>), or String
    if (mobdaten is XmlDocument) {
      _mobdaten = mobdaten;
    } else if (mobdaten is List<int>) {
      final xmlString = String.fromCharCodes(mobdaten);
      _mobdaten = XmlDocument.parse(xmlString);
    } else if (mobdaten is String) {
      _mobdaten = XmlDocument.parse(mobdaten);
    } else {
      print(mobdaten.runtimeType);
      throw ArgumentError('mobdaten must be XmlDocument, List<int>, or String');
    }

    _dataroot = _mobdaten.rootElement;

    // Parse zeitstempel
    final kopfElements = _mobdaten.findAllElements('Kopf').toList();
    if (kopfElements.isEmpty) {
      throw Exceptions.XMLNotFound('Kopf-Element nicht gefunden');
    }
    final zeitstempelElements = kopfElements.first.findElements('zeitstempel').toList();
    if (zeitstempelElements.isEmpty) {
      throw Exceptions.XMLNotFound('zeitstempel-Element nicht gefunden');
    }
    final zeitstempelText = zeitstempelElements.first.innerText;
    zeitstempel = _parseDateTime(zeitstempelText, '%d.%m.%Y, %H:%M');

    // Parse datei
    final dateiElements = kopfElements.first.findElements('datei').toList();
    if (dateiElements.isEmpty) {
      throw Exceptions.XMLNotFound('datei-Element nicht gefunden');
    }
    datei = dateiElements.first.innerText;

    try{
    datum = _parseDate(datei.substring(6, 14), '%Y%m%d');
    } catch(e){
      regulaerPlan=true;
      datum = datumP!;
    }

    wochentag = datum.weekday - 1;

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

  DateTime _parseDateTime(String dateStr, String format) {
    final parts = dateStr.split(', ');
    final dateParts = parts[0].split('.');
    final timeParts = parts[1].split(':');
    
    return DateTime(
      int.parse(dateParts[2]),
      int.parse(dateParts[1]),
      int.parse(dateParts[0]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
  }

  DateTime _parseDate(String dateStr, String format) {
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

      for (var std in alleStd) {
        if (!std.anders && !std.ausfall && !std.besonders) {
          for (var sr in std.lehrer.split(' ')) {
            if (sr.isNotEmpty) {
              leNichtKrank.add(sr);
              if (leKrank.contains(sr)) {
                leKrank.remove(sr);
              }
            }
          }
        } else if (std.anders && !std.ausfall && !std.besonders) {
          for (var sr in std.lehrer.split(' ')) {
            if (sr.isNotEmpty) {
              leNichtKrank.add(sr);
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
            if (!leNichtKrank.contains(le['kurz'])) {
              if (!leKrank.contains(le['kurz'])) {
                leKrank.add(le['kurz']!);
              }
            }
          } catch (e) {
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

    leKrank.sort();
    return leKrank;
  }

  void saveasfile({String pfad = './datei.xml', bool overwrite = false}) {
    final xmlpretty = prettyxml(_mobdaten);

    final zielpfad = File(pfad).absolute.path;
    final directory = File(zielpfad).parent.path;

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
  late int maximumStunde;

  Klasse({required XmlElement xmldata}) {
    _data = xmldata;
    final kurzElements = _data.findElements('Kurz').toList();
    if (kurzElements.isEmpty) {
      throw Exceptions.XMLNotFound('Kurz-Element in Klasse nicht gefunden');
    }
    kuerzel = kurzElements.first.innerText;
  }

  @override
  String toString() {
    return 'Vertretungsplan der Klasse $kuerzel';
  }

  List<Stunde> stundenInPeriode(int periode) {
    List<Stunde> fin = [];
    final plElements = _data.findElements('Pl').toList();
    
    if (plElements.isEmpty) {
      throw Exceptions.XMLNotFound(
          'Keine Stunden zu dieser Stundenplanperiode gefunden!');
    }

    final pl = plElements.first;
    for (var std in pl.findElements('Std')) {
      final stElements = std.findElements('St').toList();
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
    final plElements = _data.findElements('Pl').toList();
    
    if (plElements.isEmpty) {
      throw Exceptions.XMLNotFound('Keine Stunden fuer diese Klasse gefunden!');
    }

    final pl = plElements.first;
    for (var std in pl.findElements('Std')) {
      late dynamic stElements;
      if(std.findElements('St').isEmpty){
        stElements = std.findElements('PlSt');
      } else {
        stElements = std.findElements('St');
      }
      
      if (stElements.isNotEmpty) {
        Stunde stunde = Stunde(xmldata: std);
        if (stunde.nr > maximumStunde) {
          maximumStunde = stunde.nr;
        }
        fin.add(stunde);
      }
    }

    if (fin.isNotEmpty) {
      
      return fin;
    } else {
      throw Exceptions.XMLNotFound('Keine Stunden fuer diese Klasse gefunden!');//Todo: Fix load error ??
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
  late TimeOfDay beginn;
  late TimeOfDay ende;
  late bool anders;
  late bool ausfall;
  late bool besonders;
  late int kursnummer;
  late String fach;
  late String lehrer;
  late String raum;
  late String info;

  Stunde({required dynamic xmldata}) {
    if (xmldata is XmlElement) {
      _data = xmldata;
    } else if (xmldata is List<int>) {
      final xmlString = String.fromCharCodes(xmldata);
      _data = XmlDocument.parse(xmlString).rootElement;
    } else if (xmldata is String) {
      _data = XmlDocument.parse(xmldata).rootElement;
    } else {
      throw ArgumentError('xmldata must be XmlElement, List<int>, or String');
    }


    final stAlternativElements = _data.findElements('StAlternativ').toList();
    final nrElements = _data.findElements('St').toList();
    
    if (stAlternativElements.isNotEmpty && stAlternativElements.first.innerText.isNotEmpty) {
      nr = int.parse(stAlternativElements.first.innerText);
    } else if (nrElements.isNotEmpty) {
      nr = int.parse(nrElements.first.innerText);
    } else {
      throw Exceptions.XMLNotFound('Stunde Nr nicht gefunden');
    }

    final beginnElements = _data.findElements('Beginn').toList();
    if (beginnElements.isEmpty) {
      throw Exceptions.XMLNotFound('Beginn-Element nicht gefunden');
    }
    String beginn_str = beginnElements.first.innerText;

    final endeElements = _data.findElements('Ende').toList();
    if (endeElements.isEmpty) {
      throw Exceptions.XMLNotFound('Ende-Element nicht gefunden');
    }
    String ende_str = endeElements.first.innerText;

    beginn = TimeOfDay(
      hour: int.parse(beginn_str.split(':')[0]),
      minute: int.parse(beginn_str.split(':')[1]),
    );

    ende = TimeOfDay(
      hour: int.parse(ende_str.split(':')[0]),
      minute: int.parse(ende_str.split(':')[1]),
    );

    final faElements = _data.findElements('Fa').toList();
    final raElements = _data.findElements('Ra').toList();
    final leElements = _data.findElements('Le').toList();
    
    if (faElements.isEmpty || raElements.isEmpty || leElements.isEmpty) {
      throw Exceptions.XMLNotFound('Fa, Ra oder Le Element nicht gefunden');
    }
    
    final faElement = faElements.first;
    final raElement = raElements.first;
    final leElement = leElements.first;

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
      final nrEl = _data.findElements('Nr').toList();
      if (nrEl.isNotEmpty) {
        kursnummer = int.parse(nrEl.first.innerText);
      } else {
        besonders = true;
        kursnummer = -1;
      }
    } catch (e) {
      besonders = true;
      kursnummer = -1;
    }

    String fachTemp;
    final faEl = _data.findElements('Fa').toList();
    if (faEl.isNotEmpty && faEl.first.innerText.isNotEmpty) {
      fachTemp = faEl.first.innerText;
    } else {
      fachTemp = '';
    }
    fach = (!ausfall && !besonders) ? fachTemp : '';

    String tmpLe;
    final leEl = _data.findElements('Le').toList();
    if (leEl.isNotEmpty && leEl.first.innerText.isNotEmpty) {
      tmpLe = leEl.first.innerText;
    } else {
      tmpLe = '';
    }
    lehrer = !ausfall ? tmpLe : '';

    String tmpRa;
    final raEl = _data.findElements('Ra').toList();
    if (raEl.isNotEmpty && raEl.first.innerText.isNotEmpty) {
      tmpRa = raEl.first.innerText;
    } else {
      tmpRa = '';
    }
    raum = !ausfall ? tmpRa : '';

    final ifElements = _data.findElements('If').toList();
    info = ifElements.isNotEmpty ? ifElements.first.innerText : '';
  }

  @override
  String toString() {
    return 'Stundenobjekt der $nr. Stunde bei $lehrer';
  }
}

class Kurs {
  late XmlElement _data;
  late String lehrer;
  late String fach;
  late String zusatz;
  late String kursnummer;

  Kurs(dynamic xmldata) {
    XmlElement tempData;
    
    if (xmldata is XmlElement) {
      tempData = xmldata;
    } else if (xmldata is List<int>) {
      final xmlString = String.fromCharCodes(xmldata);
      tempData = XmlDocument.parse(xmlString).rootElement;
    } else if (xmldata is String) {
      tempData = XmlDocument.parse(xmldata).rootElement;
    } else {
      throw ArgumentError('xmldata must be XmlElement, List<int>, or String');
    }

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
