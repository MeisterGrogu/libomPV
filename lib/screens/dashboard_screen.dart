import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/dashboard_provider.dart';
import '../models/homework_task.dart';

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