import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../backend/fetcher.dart';
import '../backend/parser.dart';
import '../backend/teacher_lookup_table.dart';
import '../providers/dashboard_provider.dart';

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

  // New strict Mon-Fri lists and map
  List<DateTime> _calendarDays = [];
  Map<DateTime, VpDay> _fetchedDays = {};
  String _errorMessage = '';

  @override
  bool get wantKeepAlive => true;

  /// Converts teacher abbreviations to full names
  /// Example: "HPl SZi" -> "Herr Plath, Frau Scholze Zimmermann"
  String _getFullTeacherNames(String teacherAbbreviations) {
    if (teacherAbbreviations.isEmpty) return '';
    
    final abbreviations = teacherAbbreviations.split(' ');
    final fullNames = <String>[];
    
    for (final abbr in abbreviations) {
      if (abbr.isNotEmpty && teacherLookupTable.containsKey(abbr)) {
        fullNames.add(teacherLookupTable[abbr]!);
      }
    }
    
    return fullNames.join(', ');
  }

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
    final isWeekView = provider.isWeekView;

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
            icon: Icon(isWeekView ? Icons.calendar_view_day_rounded : Icons.calendar_view_week_rounded),
            tooltip: isWeekView ? "Tagesansicht" : "Wochenansicht",
            onPressed: () {
              provider.setWeekView(!isWeekView);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? const Center(child: Text('Kein Plan verfügbar'))
          : _calendarDays.isEmpty
          ? const Center(child: Text('Keine Daten verfügbar'))
          : isWeekView
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
                            s.fach.isNotEmpty ? s.fach : 'Vertretung / Info',
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
                                  Text(_getFullTeacherNames(s.lehrer), style: const TextStyle(fontSize: 12, color: Colors.white70)),
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