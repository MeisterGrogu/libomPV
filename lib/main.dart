import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'backend/fetcher.dart';
import 'backend/parser.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DashboardProvider()..refreshData()),
      ],
      child: const SchulCockpitApp(),
    ),
  );
}

class SchulCockpitApp extends StatelessWidget {
  const SchulCockpitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchulCockpit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const MainScreen(),
    );
  }
}

class HomeworkTask {
  final String id;
  final String subject;
  final String task;
  final DateTime dueDate;
  bool isDone;

  HomeworkTask({
    required this.id,
    required this.subject,
    required this.task,
    required this.dueDate,
    this.isDone = false,
  });
}

class DashboardProvider with ChangeNotifier {
  final int _schulnummer = 40102573;
  final String _benutzername = "schueler";
  final String _passwort = "AEG_2526_S";

  String _klasseKuerzel = "9a";
  String get klasseKuerzel => _klasseKuerzel;

  VpDay? _currentDayData;
  bool _isLoading = false;

  final List<HomeworkTask> _localHomework = [
    HomeworkTask(id: '1', subject: 'Mathe', task: 'S. 42 Nr. 1-5', dueDate: DateTime.now()),
  ];

  bool get isLoading => _isLoading;
  List<HomeworkTask> get todayHomework => _localHomework.where((hw) => !hw.isDone && DateUtils.isSameDay(hw.dueDate, DateTime.now())).toList();

  void setKlasse(String neueKlasse) {
    _klasseKuerzel = neueKlasse;
    refreshData();
  }

  Future<void> refreshData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final vp = Vertretungsplan(
        schulnummer: _schulnummer,
        benutzername: _benutzername,
        passwort: _passwort,
      );
      _currentDayData = await vp.fetch(datum: DateTime.now());
    } catch (e) {
      debugPrint("Fehler beim Laden: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  Map<String, dynamic>? getNextLesson() {
    if (_currentDayData == null) return null;
    try {
      final kl = _currentDayData!.klasse(_klasseKuerzel);
      final stunden = kl.stunden();
      if (stunden.isEmpty) return null;

      final now = DateTime.now();

      for (var s in stunden) {
        final endDateTime = DateTime(now.year, now.month, now.day, s.ende.hour, s.ende.minute);

        if (now.isBefore(endDateTime)) {
          return {
            'nr': s.nr,
            'fach': s.ausfall ? 'FÄLLT AUS' : (s.fach.isNotEmpty ? s.fach : '—'),
            'raum': s.raum,
            'isCancelled': s.ausfall,
          };
        }
      }

      return {
        'nr': '—',
        'fach': 'Schulschluss! 🎉',
        'raum': 'Zuhause',
        'isCancelled': false,
      };

    } catch (e) {
      return null;
    }
  }

  void toggleHomework(String id) {
    final index = _localHomework.indexWhere((hw) => hw.id == id);
    if (index >= 0) {
      _localHomework[index].isDone = !_localHomework[index].isDone;
      notifyListeners();
    }
  }

  void addHomework(String subject, String task, DateTime date) {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    _localHomework.add(HomeworkTask(
      id: newId,
      subject: subject,
      task: task,
      dueDate: date,
    ));
    notifyListeners();
  }

  List<HomeworkTask> getHomeworkForDate(DateTime date) {
    return _localHomework.where((hw) =>
    hw.dueDate.year == date.year &&
        hw.dueDate.month == date.month &&
        hw.dueDate.day == date.day
    ).toList();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const TimetablePage(),
    const HomeworkCalendarScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'Aufgaben',
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  void _showSettingsDialog(BuildContext context) {
    final provider = Provider.of<DashboardProvider>(context, listen: false);
    final controller = TextEditingController(text: provider.klasseKuerzel);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Klasse ändern"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Klasse (z.B. 9a, 10b)",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Abbrechen")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.setKlasse(controller.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text("Speichern"),
          ),
        ],
      ),
    );
  }

  void _showAddHomeworkSheet(BuildContext context) {
    final subjectController = TextEditingController();
    final taskController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20, right: 20, top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Neue Hausaufgabe", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: subjectController,
                    decoration: const InputDecoration(labelText: "Fach", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: taskController,
                    decoration: const InputDecoration(labelText: "Aufgabe", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("Fällig am: ${DateFormat('dd.MM.yyyy').format(selectedDate)}"),
                    trailing: const Icon(Icons.calendar_month, color: Colors.deepPurpleAccent),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                      onPressed: () {
                        if (subjectController.text.isNotEmpty && taskController.text.isNotEmpty) {
                          Provider.of<DashboardProvider>(context, listen: false)
                              .addHomework(subjectController.text, taskController.text, selectedDate);
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Speichern"),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DashboardProvider>(context);
    final nextLesson = provider.getNextLesson();
    final todayString = DateFormat('EEEE', 'de_DE').format(DateTime.now());

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(todayString),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: "Klasse ändern",
                onPressed: () => _showSettingsDialog(context),
              ),
              const SizedBox(width: 10),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("KLASSE ${provider.klasseKuerzel.toUpperCase()} • ALS NÄCHSTES", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),

                  provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildNextLessonCard(context, nextLesson),

                  const SizedBox(height: 30),

                  const Text("HEUTE FÄLLIG", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 10),

                  if (provider.todayHomework.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("Keine Hausaufgaben für heute! 🎉", style: TextStyle(fontSize: 16)),
                    ),

                  ...provider.todayHomework.map((hw) => _buildHomeworkTile(context, hw)).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddHomeworkSheet(context),
        label: const Text("Hausaufgabe"),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildNextLessonCard(BuildContext context, Map<String, dynamic>? lesson) {
    if (lesson == null) {
      return const Card(child: ListTile(title: Text("Keine Stundenplandaten verfügbar")));
    }

    bool isDone = lesson['fach'] == 'Schulschluss! 🎉';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: lesson['isCancelled']
              ? [Colors.red.shade900, Colors.red.shade700]
              : (isDone
              ? [Colors.green.shade800, Colors.green.shade600]
              : [Colors.deepPurple.shade800, Colors.deepPurple.shade600]),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isDone ? "FEIERABEND" : "${lesson['nr']}. STUNDE", style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 5),
          Text(lesson['fach'], style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(isDone ? Icons.home : Icons.location_on, color: Colors.white70, size: 18),
              const SizedBox(width: 5),
              Text(lesson['raum'] ?? "Kein Raum", style: const TextStyle(color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHomeworkTile(BuildContext context, HomeworkTask hw) {
    final provider = Provider.of<DashboardProvider>(context, listen: false);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.shade200,
          child: Text(hw.subject[0], style: const TextStyle(color: Colors.black)),
        ),
        title: Text(hw.task, style: TextStyle(decoration: hw.isDone ? TextDecoration.lineThrough : null)),
        subtitle: Text(hw.subject),
        trailing: Checkbox(
          value: hw.isDone,
          onChanged: (val) => provider.toggleHomework(hw.id),
        ),
      ),
    );
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  final int schulnummer = 40102573;
  final String benutzername = "schueler";
  final String passwort = "AEG_2526_S";

  late final Vertretungsplan _vp;

  String _getGermanWeekday(int weekday) {
    const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    return days[weekday - 1];
  }

  @override
  void initState() {
    super.initState();
    _vp = Vertretungsplan(schulnummer: schulnummer, benutzername: benutzername, passwort: passwort);
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
    final provider = Provider.of<DashboardProvider>(context);
    final klasseKuerzel = provider.klasseKuerzel;

    return Scaffold(
      appBar: AppBar(
        title: Text('Plan für $klasseKuerzel'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<VpDay>>(
        future: _fetchWeek(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Keine Daten verfügbar'));
          }

          final week = snapshot.data!;

          return DefaultTabController(
            length: week.length,
            initialIndex: (DateTime.now().weekday <= 5) ? DateTime.now().weekday - 1 : 0,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  indicatorColor: Colors.deepPurple,
                  tabs: week.map((day) => Tab(
                    text: "${_getGermanWeekday(day.datum.weekday)}\n${DateFormat('dd.MM.').format(day.datum)}",
                  )).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: week.map((vpday) {
                      try {
                        final kl = vpday.klasse(klasseKuerzel);
                        final stunden = kl.stunden();

                        if (stunden.isEmpty) {
                          return const Center(child: Text("Keine Stunden eingetragen."));
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: stunden.length,
                          itemBuilder: (context, i) {
                            final s = stunden[i];
                            final isCancelled = s.ausfall;
                            final title = isCancelled ? 'Ausfall' : (s.fach.isNotEmpty ? s.fach : 'Freistunde');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: isCancelled ? 0 : 2,
                              color: isCancelled ? Colors.red.withOpacity(0.1) : Theme.of(context).cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: isCancelled ? const BorderSide(color: Colors.redAccent, width: 1) : BorderSide.none,
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isCancelled ? Colors.redAccent : Colors.deepPurple.withOpacity(0.2),
                                  foregroundColor: isCancelled ? Colors.white : Colors.white,
                                  child: Text("${s.nr}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                title: Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                                      color: isCancelled ? Colors.redAccent : null,
                                    )
                                ),
                                subtitle: Text(s.raum.isNotEmpty ? "Raum: ${s.raum}" : "Kein Raum angegeben"),
                                trailing: isCancelled ? const Icon(Icons.cancel_outlined, color: Colors.redAccent) : null,
                              ),
                            );
                          },
                        );
                      } catch (e) {
                        return const Center(child: Text('Für diesen Tag sind keine Daten verfügbar.'));
                      }
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HomeworkCalendarScreen extends StatefulWidget {
  const HomeworkCalendarScreen({super.key});

  @override
  State<HomeworkCalendarScreen> createState() => _HomeworkCalendarScreenState();
}

class _HomeworkCalendarScreenState extends State<HomeworkCalendarScreen> {
  late PageController _pageController;
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 500);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('MMMM yyyy', 'de_DE').format(_focusedMonth)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
                  .map((d) => Expanded(
                child: Center(
                    child: Text(d,
                        style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold))),
              ))
                  .toList(),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _focusedMonth = DateTime(
                    DateTime.now().year,
                    DateTime.now().month + (index - 500),
                  );
                });
              },
              itemBuilder: (context, index) {
                final monthDate = DateTime(
                  DateTime.now().year,
                  DateTime.now().month + (index - 500),
                );
                return _buildMonthGrid(monthDate);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthGrid(DateTime month) {
    final provider = Provider.of<DashboardProvider>(context);

    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);

    final leadingSpaces = firstDayOfMonth.weekday - 1;
    final totalCells = leadingSpaces + lastDayOfMonth.day;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.6,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        if (index < leadingSpaces) return const SizedBox.shrink();

        final dayNumber = index - leadingSpaces + 1;
        final date = DateTime(month.year, month.month, dayNumber);
        final tasks = provider.getHomeworkForDate(date);
        final isToday = DateUtils.isSameDay(date, DateTime.now());

        return GestureDetector(
          onTap: () => _showAddHomeworkSheet(context, date),
          child: Container(
            decoration: BoxDecoration(
              color: isToday ? Colors.deepPurple.withOpacity(0.1) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: isToday ? Border.all(color: Colors.deepPurpleAccent, width: 1) : null,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.deepPurpleAccent : Colors.transparent,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: Center(
                    child: Text("$dayNumber.",
                        style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: tasks.map((t) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
                        padding: const EdgeInsets.all(2),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: t.isDone ? Colors.green.withOpacity(0.4) : Colors.deepPurple.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(t.subject, style: const TextStyle(fontSize: 8, color: Colors.white), overflow: TextOverflow.ellipsis),
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddHomeworkSheet(BuildContext context, DateTime targetDate) {
    final subjectController = TextEditingController();
    final taskController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Hausaufgabe für den ${DateFormat('dd.MM.').format(targetDate)}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            TextField(controller: subjectController, decoration: const InputDecoration(labelText: "Fach", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: taskController, decoration: const InputDecoration(labelText: "Aufgabe", border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: () {
                  if (subjectController.text.isNotEmpty && taskController.text.isNotEmpty) {
                    Provider.of<DashboardProvider>(context, listen: false)
                        .addHomework(subjectController.text, taskController.text, targetDate);
                    Navigator.pop(context);
                  }
                },
                child: const Text("Speichern"),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}