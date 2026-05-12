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

  /// Converts HomeworkTask to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'subject': subject,
    'task': task,
    'dueDate': dueDate.toIso8601String(),
    'isDone': isDone,
  };

  /// Creates HomeworkTask from JSON
  factory HomeworkTask.fromJson(Map<String, dynamic> json) => HomeworkTask(
    id: json['id'] as String,
    subject: json['subject'] as String,
    task: json['task'] as String,
    dueDate: DateTime.parse(json['dueDate'] as String),
    isDone: json['isDone'] as bool? ?? false,
  );
}