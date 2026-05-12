import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/homework_task.dart';
import '../backend/fetcher.dart';
import '../backend/parser.dart';

class DashboardProvider with ChangeNotifier {
  final int _schulnummer = 40102573;
  final String _benutzername = "schueler";
  final String _passwort = "AEG_2526_S";

  // Storage keys
  static const String _klasseKey = 'dashboard_klasse';
  static const String _homeworkKey = 'dashboard_homework';
  static const String _weekViewKey = 'dashboard_week_view';

  late SharedPreferences _prefs;
  bool _initialized = false;

  String _klasseKuerzel = "9a";
  String get klasseKuerzel => _klasseKuerzel;

  VpDay? _currentDayData;
  bool _isLoading = false;
  DateTime? _lastUpdated;
  bool _hasFetched = false;
  bool _isWeekend = false;
  
  bool _isWeekView = false;
  bool get isWeekView => _isWeekView;

  final List<HomeworkTask> _localHomework = [];

  bool get isLoading => _isLoading;
  List<HomeworkTask> get todayHomework => _localHomework.where((hw) => !hw.isDone && DateUtils.isSameDay(hw.dueDate, DateTime.now())).toList();
  DateTime? get lastUpdated => _lastUpdated;

  /// Initialize the provider with SharedPreferences and load persisted data
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    await _loadData();
    _initialized = true;
  }

  /// Load all persisted data from SharedPreferences
  Future<void> _loadData() async {
    // Load class
    final savedKlasse = _prefs.getString(_klasseKey);
    if (savedKlasse != null) {
      _klasseKuerzel = savedKlasse;
    }

    // Load homework tasks
    final savedHomework = _prefs.getString(_homeworkKey);
    if (savedHomework != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(savedHomework);
        _localHomework.clear();
        _localHomework.addAll(
          decodedList.map((item) => HomeworkTask.fromJson(item as Map<String, dynamic>)).toList(),
        );
      } catch (e) {
        debugPrint('Error loading homework: $e');
      }
    }

    // Load week view preference
    _isWeekView = _prefs.getBool(_weekViewKey) ?? false;

    notifyListeners();
  }

  /// Save all data to SharedPreferences
  Future<void> _saveData() async {
    if (!_initialized) return;
    await Future.wait([
      _prefs.setString(_klasseKey, _klasseKuerzel),
      _prefs.setString(_homeworkKey, jsonEncode(_localHomework.map((hw) => hw.toJson()).toList())),
      _prefs.setBool(_weekViewKey, _isWeekView),
    ]);
  }

  void setKlasse(String neueKlasse) {
    _klasseKuerzel = neueKlasse;
    _saveData();
    notifyListeners();
  }

  void setWeekView(bool isWeek) {
    _isWeekView = isWeek;
    _saveData();
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
      _saveData();
      notifyListeners();
    }
  }

  void addHomework(String subject, String task, DateTime date) {
    _localHomework.add(HomeworkTask(id: DateTime.now().millisecondsSinceEpoch.toString(), subject: subject, task: task, dueDate: date));
    _saveData();
    notifyListeners();
  }

  void deleteHomework(String id) {
    _localHomework.removeWhere((hw) => hw.id == id);
    _saveData();
    notifyListeners();
  }

  List<HomeworkTask> getHomeworkForDate(DateTime date) {
    return _localHomework.where((hw) => DateUtils.isSameDay(hw.dueDate, date)).toList();
  }
}