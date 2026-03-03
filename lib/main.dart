import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add this import for date formatting
import '../backend/fetcher.dart';
import '../backend/parser.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'libomPV',
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const TimetablePage(),
    );
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  // Example/default credentials (taken from backend_test.dart)
  final int schulnummer = 40102573;
  final String benutzername = "schueler";
  final String passwort = "AEG_2526_S";
  final String klasseKuerzel = "9d";

  late final Vertretungsplan _vp;

  @override
  void initState() {
    super.initState();
    _vp = Vertretungsplan(
      schulnummer: schulnummer,
      benutzername: benutzername,
      passwort: passwort,
    );
  }

  Future<List<VpDay>> _fetchWeek() async {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final days = <VpDay>[];
    for (int i = 0; i < 5; i++) {
      final date = monday.add(Duration(days: i));
      days.add(await _vp.fetch(datum: date));
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: 
          TextButton(
            onPressed: (){
            }, 
            child: Text('Plan')),
        title: const Text('Timetable'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: (){
            }, 
            child: Text('Einstellung'))
          ],
      ),
      body: FutureBuilder<List<VpDay>>(
        future: _fetchWeek(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No data'));
          }

          final week = snapshot.data!;
          return ListView(
            children: week.map((vpday) {
              try {
                final kl = vpday.klasse(klasseKuerzel);
                final stunden = kl.stunden();
                final dateFormatted = DateFormat('EEEE, dd.MM.yyyy').format(vpday.datum); // Format the date
                return ExpansionTile(
                  title: Text(dateFormatted),
                  children: stunden.map((s) {
                    final title = s.ausfall ? 'Ausfall' : (s.fach.isNotEmpty ? s.fach : '—');
                    final subtitle = s.ausfall
                        ? 'Kein Unterricht'
                        : '${s.lehrer.isNotEmpty ? s.lehrer : 'unbekannt'} • ${s.raum.isNotEmpty ? s.raum : 'kein Raum'}';
                    return ListTile(
                      leading: CircleAvatar(child: Text(s.nr.toString())),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: Text('${s.beginn}–${s.ende}'),
                    );
                  }).toList(),
                );
              } catch (e) {
                final dateFormatted = DateFormat('EEEE, dd.MM.yyyy').format(vpday.datum);
                return ListTile(title: Text('Klasse $klasseKuerzel not found for $dateFormatted'));
              }
            }).toList(),
          );
        },
      ),
    );
  }
}
