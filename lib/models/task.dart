class Task {
  String id;
  String title;
  String description;
  bool isCompleted;
  DateTime? startDate;
  DateTime? dueDate;
  DateTime? completedAt;
  bool hasDueDate;

  Task({
    required this.id,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.startDate,
    this.dueDate,
    this.completedAt,
    this.hasDueDate = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'isCompleted': isCompleted,
    'startDate': startDate?.toIso8601String(),
    'dueDate': dueDate?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'hasDueDate': hasDueDate,
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'],
    title: json['title'],
    description: json['description'] ?? '',
    isCompleted: json['isCompleted'] ?? false,
    startDate: json['startDate'] != null
        ? DateTime.parse(json['startDate'])
        : null,
    dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'])
        : null,
    hasDueDate:
        json['hasDueDate'] ??
        (json['dueDate'] != null || json['startDate'] != null),
  );
}
