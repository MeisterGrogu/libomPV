import 'package:http/http.dart' as http;
import 'dart:convert';

import 'exceptions.dart';
import 'parser.dart';

class Vertretungsplan {
  final int schulnummer;
  final String benutzername;
  final String passwort;
  final String _webpath;
  final String _dateinamenschema;
  static final Map<String, VpDay> _cache = {};

  Vertretungsplan({
    required this.schulnummer,
    required this.benutzername,
    required this.passwort,
    String serverurl = "stundenplan24.de",
    String verzeichnis = "{schulnummer}/mobil/mobdaten",
    String dateinamenschema = "PlanKl%Y%m%d.xml",
  })  : _dateinamenschema = dateinamenschema,
        _webpath = _buildWebpath(
          benutzername: benutzername,
          passwort: passwort,
          serverurl: serverurl,
          verzeichnis: verzeichnis,
          schulnummer: schulnummer,
        );

  static String _buildWebpath({
    required String benutzername,
    required String passwort,
    required String serverurl,
    required String verzeichnis,
    required int schulnummer,
  }) {
    String processedServerurl = serverurl;
    String processedVerzeichnis = verzeichnis;
    
    if (processedServerurl.endsWith("/")) {
      processedServerurl = processedServerurl.substring(0, processedServerurl.length - 1);
    }

    if (processedServerurl.startsWith("http://") || processedServerurl.startsWith("https://")) {
      final parts = processedServerurl.split("://");
      processedServerurl = parts.length > 1 ? parts[1] : parts[0];
    }

    if (processedVerzeichnis.endsWith("/")) {
      processedVerzeichnis = processedVerzeichnis.substring(0, processedVerzeichnis.length - 1);
    }

    if (processedVerzeichnis.startsWith("/")) {
      processedVerzeichnis = processedVerzeichnis.substring(1);
    }

    processedVerzeichnis = processedVerzeichnis.replaceAll("{schulnummer}", schulnummer.toString());

    return "$processedServerurl/$processedVerzeichnis";
  }

  @override
  String toString() {
    return "Vertretungsplan $benutzername@$schulnummer";
  }

  Future<VpDay> fetch({
    dynamic datum,
    String? datei,
  }) async {
    datum ??= DateTime.now();

    DateTime datumDate;
    if (datum is int) {
      final datumStr = datum.toString();
      final year = int.parse(datumStr.substring(0, 4));
      final month = int.parse(datumStr.substring(4, 6));
      final day = int.parse(datumStr.substring(6, 8));
      datumDate = DateTime(year, month, day);
    } else if (datum is DateTime) {
      datumDate = datum;
    } else {
      throw ArgumentError('datum must be either DateTime or int');
    }

    String file;
    if (datei == null) {
      file = _formatDateToFilename(datumDate, _dateinamenschema);
    } else {
      file = datei.replaceAll("{schulnummer}", schulnummer.toString());
    }
    if (_cache.containsKey(file)) {
      return _cache[file]!;
    }

    final uri = Uri.parse("https://$_webpath/$file");

    final String _basicAuth = base64Encode(utf8.encode('$benutzername:$passwort'));
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Basic $_basicAuth'},
    );

    final httpStatusCode = response.statusCode;
    if (httpStatusCode == 200) {
      final decodedBody = utf8.decode(response.bodyBytes);
      final day = VpDay(decodedBody);
      _cache[file] = day;
      return day;
    } else if (httpStatusCode == 401) {
      throw InvalidCredentialsError(
        "Passwort oder Benutzername sind ungültig.",
        statusCode: httpStatusCode,
      );
    } else if (httpStatusCode == 404) {
      throw FetchingError(
        "Datei $datei konnte nicht abgerufen werden. Entweder existiert sie nicht, oder die Schulnummer $schulnummer ist nicht registriert.",
        statusCode: httpStatusCode,
      );
    } else {
      throw FetchingError(
        "HTTP Error: ${response.statusCode} - ${response.reasonPhrase}",
        statusCode: httpStatusCode,
      );
    }
  }

  String _formatDateToFilename(DateTime date, String schema) {
    String result = schema;
    
    result = result.replaceAll('%Y', date.year.toString().padLeft(4, '0'));
    result = result.replaceAll('%y', (date.year % 100).toString().padLeft(2, '0'));
    
    result = result.replaceAll('%m', date.month.toString().padLeft(2, '0'));
    
    result = result.replaceAll('%d', date.day.toString().padLeft(2, '0'));
    
    result = result.replaceAll('%H', date.hour.toString().padLeft(2, '0'));
    result = result.replaceAll('%I', ((date.hour % 12) == 0 ? 12 : (date.hour % 12)).toString().padLeft(2, '0'));
    
    result = result.replaceAll('%M', date.minute.toString().padLeft(2, '0'));
    
    result = result.replaceAll('%S', date.second.toString().padLeft(2, '0'));
    
    return result;
  }

  Future<List<VpDay>> fetchall() async {
    final today = DateTime.now();
    final startDate = today.subtract(const Duration(days: 30));
    final endDate = today.add(const Duration(days: 30));

    final plans = <VpDay>[];

    for (final tag in _dateRange(startDate, endDate)) {
      if (tag.weekday > 5) {
        continue;
      }

      try {
        final plan = await fetch(datum: tag);
        plans.add(plan);
      } on FetchingError {
        continue;
      }
    }

    if (plans.isEmpty) {
      throw FetchingError(
        "Es konnten in einem zweimonatigen",
      );
    }

    return plans;
  }

  Iterable<DateTime> _dateRange(DateTime startDate, DateTime endDate) sync* {
    DateTime currentDate = startDate;
    while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
      yield currentDate;
      currentDate = currentDate.add(const Duration(days: 1));
    }
  }
  static void clearCache() {
    _cache.clear();
  }
}
