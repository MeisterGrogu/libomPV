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
  DateTime? _lastUpdated;
  bool _hasFetched = false;
  bool _isWeekend = false;

  final List<HomeworkTask> _localHomework = [
    HomeworkTask(id: '1', subject: 'Mathe', task: 'S. 42 Nr. 1-5', dueDate: DateTime.now()),
  ];

  bool get isLoading => _isLoading;
  List<HomeworkTask> get todayHomework => _localHomework.where((hw) => !hw.isDone && DateUtils.isSameDay(hw.dueDate, DateTime.now())).toList();

  DateTime? get lastUpdated => _lastUpdated;

  void setKlasse(String neueKlasse) {
    _klasseKuerzel = neueKlasse;
    notifyListeners();
  }

  Future<void> refreshData({bool force = false}) async {
    if (_isLoading) return;
    if (_hasFetched && !force) return;
    _isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      if (now.weekday > 5) {
        _isWeekend = true;
        _lastUpdated = DateTime.now();
        _hasFetched = true;
      } else {
        if (force) {
          Vertretungsplan.clearCache();
        }
        final vp = Vertretungsplan(
          schulnummer: _schulnummer,
          benutzername: _benutzername,
          passwort: _passwort,
        );
        _currentDayData = await vp.fetch(datum: now);
        _lastUpdated = DateTime.now();
        _hasFetched = true;
        _isWeekend = false;
      }
    } catch (e) {
      debugPrint("Fehler beim Laden: $e");
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> forceRefresh() async {
    await refreshData(force: true);
  }

  Map<String, dynamic>? getNextLesson() {
    if (_isWeekend) {
      return {
        'nr': '—',
        'fach': 'Wochenende 🌴',
        'raum': 'Zuhause',
        'isCancelled': false,
      };
    }
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
      debugPrint("Fehler beim Bestimmen der nächsten Stunde: $e");
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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late PageController _pageController;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const TimetablePage(),
    const HomeworkCalendarScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!mounted) return;
      try {
        Provider.of<DashboardProvider>(context, listen: false).forceRefresh();
      } catch (_) {}
    }
  }

  void _onBottomNavTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onBottomNavTapped,
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
      body: RefreshIndicator(
        onRefresh: () => provider.forceRefresh(),
        child: CustomScrollView(
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
                    const SizedBox(height: 4),
                    if (provider.lastUpdated != null)
                      Text("Zuletzt aktualisiert: ${DateFormat('dd.MM.y HH:mm', 'de_DE').format(provider.lastUpdated!)}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 6),

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

                    ...provider.todayHomework.map((hw) => _buildHomeworkTile(context, hw)),
                  ],
                ),
              ),
            ),
          ],
        ),
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

    bool isDone = lesson['fach'] == 'Schulschluss! 🎉' || lesson['fach'] == 'Wochenende 🌴';

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

class _TimetablePageState extends State<TimetablePage> with AutomaticKeepAliveClientMixin {
  final int schulnummer = 40102573;
  final String benutzername = "schueler";
  final String passwort = "AEG_2526_S";

  late final Vertretungsplan _vp;
  bool _isLoading = true;
  bool _isWeekView = false;
  
  // New strict Mon-Fri lists and map
  List<DateTime> _calendarDays = [];
  Map<DateTime, VpDay> _fetchedDays = {};
  String _errorMessage = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _vp = Vertretungsplan(schulnummer: schulnummer, benutzername: benutzername, passwort: passwort);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final now = DateTime.now();
      // Start from the Monday of the current week
      final startMonday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      
      List<DateTime> daysToFetch = [];
      // Generate exactly 4 weeks of Mon-Fri dates
      for (int week = 0; week < 4; week++) {
        for (int day = 0; day < 5; day++) {
          daysToFetch.add(startMonday.add(Duration(days: week * 7 + day)));
        }
      }

      List<Future<void>> futures = [];
      for (var d in daysToFetch) {
        futures.add(_fetchSingleDaySafe(d).then((vpday) {
          if (vpday != null) {
            _fetchedDays[d] = vpday;
          }
        }));
      }

      await Future.wait(futures);

      if (mounted) {
        setState(() {
          _calendarDays = daysToFetch;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<VpDay?> _fetchSingleDaySafe(DateTime date) async {
    try {
      return await _vp.fetch(datum: date);
    } catch (_) {
      return null;
    }
  }

  DateTime _getTargetDate() {
    DateTime now = DateTime.now();
    DateTime target = DateTime(now.year, now.month, now.day);
    if (now.weekday == DateTime.saturday) {
      target = target.add(const Duration(days: 2));
    } else if (now.weekday == DateTime.sunday) {
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  String _getGermanWeekdayShort(int weekday) {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return days[weekday - 1];
  }

  Map<int, Stunde> _getHourMap(List<Stunde> stunden) {
    return {for (var s in stunden) s.nr: s};
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final provider = Provider.of<DashboardProvider>(context);
    final klasseKuerzel = provider.klasseKuerzel;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Plan für $klasseKuerzel'),
            if (provider.lastUpdated != null)
              Text(DateFormat('dd.MM.y HH:mm', 'de_DE').format(provider.lastUpdated!), style: const TextStyle(fontSize: 12)),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isWeekView ? Icons.calendar_view_day_rounded : Icons.calendar_view_week_rounded),
            tooltip: _isWeekView ? "Tagesansicht" : "Wochenansicht",
            onPressed: () {
              setState(() {
                _isWeekView = !_isWeekView;
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text('Fehler: $_errorMessage'))
          : _calendarDays.isEmpty
          ? const Center(child: Text('Keine Daten verfügbar'))
          : _isWeekView
          ? _buildWeekView(klasseKuerzel)
          : _buildDayView(klasseKuerzel),
    );
  }

  Widget _buildDayView(String klasseKuerzel) {
    final targetDate = _getTargetDate();
    int initialIndex = _calendarDays.indexWhere((d) => DateUtils.isSameDay(d, targetDate));
    if (initialIndex < 0) initialIndex = 0;

    return DefaultTabController(
      length: _calendarDays.length,
      initialIndex: initialIndex,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            indicatorColor: Colors.deepPurple,
            tabAlignment: TabAlignment.start,
            tabs: _calendarDays.map((date) {
              return Tab(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_getGermanWeekdayShort(date.weekday), style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(DateFormat('dd.MM.').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              );
            }).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: _calendarDays.map((date) {
                return _buildModernSingleDayList(date, klasseKuerzel);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernSingleDayList(DateTime date, String klasseKuerzel) {
    final vpday = _fetchedDays[date];
    Map<int, Stunde> hourMap = {};

    if (vpday != null) {
      try {
        final kl = vpday.klasse(klasseKuerzel);
        hourMap = _getHourMap(kl.stunden());
      } catch (_) {}
    }

    if (vpday == null || hourMap.isEmpty) {
      return const Center(child: Text('Kein Plan für diesen Tag.', style: TextStyle(color: Colors.grey)));
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Provider.of<DashboardProvider>(context, listen: false).forceRefresh();
        _loadData();
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 10, // Assuming 10 slots max
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final hour = index + 1;
          final s = hourMap[hour];
          return _buildModernLessonCard(hour, s);
        },
      ),
    );
  }

  Widget _buildModernLessonCard(int hour, Stunde? s) {
    final bool isEmpty = s == null || (s.fach.isEmpty && s.info.isEmpty);
    final bool isCancelled = s?.ausfall ?? false;
    final bool hasInfo = s?.info.isNotEmpty ?? false;

    if (isEmpty) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.05), style: BorderStyle.solid),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 50,
              child: Center(child: Text("$hour.", style: TextStyle(color: Colors.grey.withOpacity(0.5), fontWeight: FontWeight.bold))),
            ),
            VerticalDivider(color: Colors.white.withOpacity(0.05), width: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text("Freistunde", style: TextStyle(color: Colors.grey.withOpacity(0.3), fontStyle: FontStyle.italic)),
            ),
          ],
        ),
      );
    }

    // Determine Theme Color
    Color accentColor = Colors.deepPurple;
    Color bgColor = Colors.deepPurple.withOpacity(0.1);
    IconData? indicatorIcon;
    
    if (isCancelled) {
      accentColor = Colors.redAccent;
      bgColor = Colors.red.withOpacity(0.1);
      indicatorIcon = Icons.warning_amber_rounded;
    } else if (hasInfo) {
      accentColor = Colors.amber;
      bgColor = Colors.amber.withOpacity(0.05);
      indicatorIcon = Icons.info_outline_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Hour Number indicator
            Container(
              width: 50,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ),
              child: Center(
                child: Text(
                  "$hour.", 
                  style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 18)
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s!.fach.isNotEmpty ? s.fach : 'Vertretung / Info',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                              color: isCancelled ? Colors.redAccent.shade100 : Colors.white,
                            ),
                          ),
                        ),
                        if (indicatorIcon != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: Icon(indicatorIcon, color: accentColor, size: 20),
                          )
                      ],
                    ),
                    const SizedBox(height: 6),
                    
                    // Chips for Teacher & Room
                    if (!isCancelled && (s.raum.isNotEmpty || s.lehrer.isNotEmpty))
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (s.raum.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.meeting_room_rounded, size: 12, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text(s.raum, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                          if (s.lehrer.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person, size: 12, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text(s.lehrer, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      
                    // Extra Info Text
                    if (s.info.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          s.info,
                          style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView(String klasseKuerzel) {
    // Group exactly into chunks of 5
    List<List<DateTime>> weeks = [];
    for (int i = 0; i < _calendarDays.length; i += 5) {
      weeks.add(_calendarDays.sublist(i, i + 5));
    }

    final targetDate = _getTargetDate();
    int initialWeek = weeks.indexWhere((w) => w.any((d) => DateUtils.isSameDay(d, targetDate)));
    if (initialWeek < 0) initialWeek = 0;

    return PageView.builder(
      controller: PageController(initialPage: initialWeek),
      itemCount: weeks.length,
      itemBuilder: (context, index) {
        final weekDays = weeks[index];
        final monday = weekDays.first;
        final friday = weekDays.last;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                "Woche vom ${DateFormat('dd.MM.').format(monday)} - ${DateFormat('dd.MM.').format(friday)}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hour Column
                    Column(
                      children: [
                        const SizedBox(height: 45), // Offset for day headers
                        for (int i = 1; i <= 10; i++)
                          Expanded(
                            child: Container(
                              width: 25,
                              alignment: Alignment.center,
                              child: Text("$i", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),

                    // Day Columns
                    ...weekDays.map((date) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: _buildModernCompactDayColumn(date, klasseKuerzel),
                      ),
                    )).toList(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _buildModernCompactDayColumn(DateTime date, String klasseKuerzel) {
    bool isToday = DateUtils.isSameDay(date, DateTime.now());
    
    final vpday = _fetchedDays[date];
    Map<int, Stunde> hourMap = {};
    if (vpday != null) {
      try {
        hourMap = _getHourMap(vpday.klasse(klasseKuerzel).stunden());
      } catch (_) {}
    }

    return Column(
      children: [
        // Day Header
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isToday ? Colors.deepPurpleAccent : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                _getGermanWeekdayShort(date.weekday),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isToday ? Colors.white : Colors.white70),
              ),
              Text(
                DateFormat('dd.MM.').format(date),
                style: TextStyle(fontSize: 10, color: isToday ? Colors.white70 : Colors.grey),
              ),
            ],
          ),
        ),
        
        // Cells
        for (int i = 1; i <= 10; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildModernCompactCell(hourMap[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildModernCompactCell(Stunde? s) {
    final bool isEmpty = s == null || (s.fach.isEmpty && s.info.isEmpty);
    if (isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    final bool isCancelled = s.ausfall;
    final bool hasInfo = s.info.isNotEmpty;

    Color bgColor = Colors.deepPurple.withOpacity(0.3);
    Color borderColor = Colors.deepPurpleAccent.withOpacity(0.5);
    
    if (isCancelled) {
      bgColor = Colors.red.withOpacity(0.2);
      borderColor = Colors.redAccent.withOpacity(0.6);
    } else if (hasInfo) {
      bgColor = Colors.amber.withOpacity(0.15);
      borderColor = Colors.amber.withOpacity(0.6);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            s.fach.isNotEmpty ? s.fach : 'Info',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              decoration: isCancelled ? TextDecoration.lineThrough : null,
              color: isCancelled ? Colors.redAccent.shade100 : Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (!isCancelled && s.raum.isNotEmpty) 
            Text(s.raum, style: const TextStyle(fontSize: 8, color: Colors.white70), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class HomeworkCalendarScreen extends StatefulWidget {
  const HomeworkCalendarScreen({super.key});

  @override
  State<HomeworkCalendarScreen> createState() => _HomeworkCalendarScreenState();
}

class _HomeworkCalendarScreenState extends State<HomeworkCalendarScreen> with AutomaticKeepAliveClientMixin {
  late PageController _pageController;
  late DateTime _focusedMonth;
  late DateTime _baseDate;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 500);
    _baseDate = DateTime.now();
    if (_baseDate.weekday == DateTime.saturday) {
      _baseDate = _baseDate.add(const Duration(days: 2));
    } else if (_baseDate.weekday == DateTime.sunday) {
      _baseDate = _baseDate.add(const Duration(days: 1));
    }
    _focusedMonth = _baseDate;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('MMMM yyyy', 'de_DE').format(_focusedMonth)),
            Builder(
              builder: (ctx) {
                final last = Provider.of<DashboardProvider>(ctx).lastUpdated;
                if (last == null) return const SizedBox.shrink();
                return Text(DateFormat('dd.MM.y HH:mm', 'de_DE').format(last), style: const TextStyle(fontSize: 12));
              },
            )
          ],
        ),
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
                            fontWeight: FontWeight.bold)
                    )
                ),
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
                    _baseDate.year,
                    _baseDate.month + (index - 500),
                  );
                });
              },
              itemBuilder: (context, index) {
                final monthDate = DateTime(
                  _baseDate.year,
                  _baseDate.month + (index - 500),
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

    return RefreshIndicator(
      onRefresh: () async {
        await Provider.of<DashboardProvider>(context, listen: false).forceRefresh();
        setState(() {});
      },
      child: GridView.builder(
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
      ),
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