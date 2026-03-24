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
      home: TimetablePage(),
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

  void settingsMenu(){
    print("object");
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Einstellung"),
          content: Column(
            children: [
              const Text('Schulnummer'),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Gebe die Schulnummer ein.',
                ),
              ),
              const Text('Benutzername'),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Gebe den Benutzernamen ein.',
                ),
              ),
              const Text('Passwort'),
              TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Gebe das Passwort ein.',
                )
              ),
            ],
          ),
          actions: [
            MaterialButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void planMenu(){
    print("pkan");
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Pläne"),
          content: Column(
            children: [
              const Text('Plan')
            ],
          ),
          actions: [
            MaterialButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
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
            onPressed: planMenu,
            child: Text('Plan')),
        title: const Text('Timetable'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: settingsMenu,
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
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: week.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // ⬅️ days per row (use 3 on tablets if you want)
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemBuilder: (context, index) {
              final vpday = week[index];
              final dateFormatted =
              DateFormat('EEEE\ndd.MM.yyyy').format(vpday.datum);

              try {
                final kl = vpday.klasse(klasseKuerzel);
                final stunden = kl.stunden();

                return Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormatted,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Divider(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: stunden.length,
                            itemBuilder: (context, i) {
                              final s = stunden[i];
                              final title = s.ausfall
                                  ? 'Ausfall'
                                  : (s.fach.isNotEmpty ? s.fach : '—');

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      child: Text(s.nr.toString()),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        title,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              } catch (e) {
                return Card(
                  child: Center(
                    child: Text(
                      'Keine Daten\n$dateFormatted',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}
