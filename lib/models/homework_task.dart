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