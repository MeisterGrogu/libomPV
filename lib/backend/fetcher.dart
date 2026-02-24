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

  /// Helper method to build the webpath during initialization
  static String _buildWebpath({
    required String benutzername,
    required String passwort,
    required String serverurl,
    required String verzeichnis,
    required int schulnummer,
  }) {
    String processedServerurl = serverurl;
    String processedVerzeichnis = verzeichnis;

    // Remove trailing slash from serverurl
    if (processedServerurl.endsWith("/")) {
      processedServerurl = processedServerurl.substring(0, processedServerurl.length - 1);
    }

    // Remove protocol prefix from serverurl
    if (processedServerurl.startsWith("http://") || processedServerurl.startsWith("https://")) {
      final parts = processedServerurl.split("://");
      processedServerurl = parts.length > 1 ? parts[1] : parts[0];
    }

    // Remove trailing slash from verzeichnis
    if (processedVerzeichnis.endsWith("/")) {
      processedVerzeichnis = processedVerzeichnis.substring(0, processedVerzeichnis.length - 1);
    }

    // Remove leading slash from verzeichnis
    if (processedVerzeichnis.startsWith("/")) {
      processedVerzeichnis = processedVerzeichnis.substring(1);
    }

    // Format verzeichnis with schulnummer
    processedVerzeichnis = processedVerzeichnis.replaceAll("{schulnummer}", schulnummer.toString());

    // Do not include credentials in the URL; send them via Authorization header instead.
    return "$processedServerurl/$processedVerzeichnis";
  }

  @override
  String toString() {
    return "Vertretungsplan $benutzername@$schulnummer";
  }

  /// Fetches the substitution plan for a specific date
  /// 
  /// [datum] can be either a DateTime or an int in YYYYMMDD format
  /// [datei] optional custom filename
  Future<VpDay> fetch({
    dynamic datum,
    String? datei,
  }) async {
    // Default to today if datum is not provided
    datum ??= DateTime.now();

    // Convert datum to DateTime
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

    // Generate filename
    String file;
    if (datei == null) {
      file = _formatDateToFilename(datumDate, _dateinamenschema);
    } else {
      file = datei.replaceAll("{schulnummer}", schulnummer.toString());
    }

    // Use HTTPS to avoid redirects that may drop Authorization headers.
    final uri = Uri.parse("https://$_webpath/$file");

    // Send credentials using HTTP Basic Authorization header.
    // Some HTTP clients/servers do not accept credentials embedded in the URL,
    // so explicitly add the Authorization header here.
    final String _basicAuth = base64Encode(utf8.encode('$benutzername:$passwort'));
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Basic $_basicAuth'},
    );

    final httpStatusCode = response.statusCode;
    if (httpStatusCode == 200) {
      return VpDay(response.bodyBytes);
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

  /// Formats a DateTime to filename based on schema
  String _formatDateToFilename(DateTime date, String schema) {
    String result = schema;
    
    // Replace year formats
    result = result.replaceAll('%Y', date.year.toString().padLeft(4, '0'));
    result = result.replaceAll('%y', (date.year % 100).toString().padLeft(2, '0'));
    
    // Replace month formats
    result = result.replaceAll('%m', date.month.toString().padLeft(2, '0'));
    
    // Replace day formats
    result = result.replaceAll('%d', date.day.toString().padLeft(2, '0'));
    
    // Replace hour formats
    result = result.replaceAll('%H', date.hour.toString().padLeft(2, '0'));
    result = result.replaceAll('%I', ((date.hour % 12) == 0 ? 12 : (date.hour % 12)).toString().padLeft(2, '0'));
    
    // Replace minute formats
    result = result.replaceAll('%M', date.minute.toString().padLeft(2, '0'));
    
    // Replace second formats
    result = result.replaceAll('%S', date.second.toString().padLeft(2, '0'));
    
    return result;
  }

  /// Fetches all available substitution plans within a 60-day range (30 days before and after today)
  Future<List<VpDay>> fetchall() async {
    final today = DateTime.now();
    final startDate = today.subtract(const Duration(days: 30));
    final endDate = today.add(const Duration(days: 30));

    final plans = <VpDay>[];

    for (final tag in _dateRange(startDate, endDate)) {
      // Skip weekends (Saturday = 6, Sunday = 7 in Dart)
      if (tag.weekday > 5) {
        continue;
      }

      try {
        final plan = await fetch(datum: tag);
        plans.add(plan);
      } on FetchingError {
        // Continue to next date if fetching fails
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

  /// Generator for date range
  Iterable<DateTime> _dateRange(DateTime startDate, DateTime endDate) sync* {
    DateTime currentDate = startDate;
    while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
      yield currentDate;
      currentDate = currentDate.add(const Duration(days: 1));
    }
  }
}
