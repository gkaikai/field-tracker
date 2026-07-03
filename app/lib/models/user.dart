/// 用户模型
class User {
  final String id;
  final String name;
  final String phone;
  final String? departmentName;
  final String? role; // employee / admin / manager

  User({
    required this.id,
    required this.name,
    required this.phone,
    this.departmentName,
    this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        departmentName: json['departmentName'],
        role: json['role'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'departmentName': departmentName,
        'role': role,
      };
}
