import 'package:flutter/material.dart';
import '../models/homework_task.dart';
import '../backend/fetcher.dart';
import '../backend/parser.dart';

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
        if (force) Vertretungsplan.clearCache();
        final vp = Vertretungsplan(schulnummer: _schulnummer, benutzername: _benutzername, passwort: _passwort);
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

  Future<void> forceRefresh() async => await refreshData(force: true);

  Map<String, dynamic>? getNextLesson() {
    if (_isWeekend) return {'nr': '—', 'fach': 'Wochenende 🌴', 'raum': 'Zuhause', 'isCancelled': false};
    if (_currentDayData == null) return null;
    try {
      final kl = _currentDayData!.klasse(_klasseKuerzel);
      final stunden = kl.stunden();
      if (stunden.isEmpty) return null;
      final now = DateTime.now();
      for (var s in stunden) {
        final endDateTime = DateTime(now.year, now.month, now.day, s.ende.hour, s.ende.minute);
        if (now.isBefore(endDateTime)) {
          return {'nr': s.nr, 'fach': s.ausfall ? 'FÄLLT AUS' : (s.fach.isNotEmpty ? s.fach : '—'), 'raum': s.raum, 'isCancelled': s.ausfall};
        }
      }
      return {'nr': '—', 'fach': 'Schulschluss! 🎉', 'raum': 'Zuhause', 'isCancelled': false};
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
    _localHomework.add(HomeworkTask(id: DateTime.now().millisecondsSinceEpoch.toString(), subject: subject, task: task, dueDate: date));
    notifyListeners();
  }

  List<HomeworkTask> getHomeworkForDate(DateTime date) {
    return _localHomework.where((hw) => DateUtils.isSameDay(hw.dueDate, date)).toList();
  }
}