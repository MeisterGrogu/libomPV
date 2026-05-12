import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';

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