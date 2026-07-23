import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.role,
    this.displayName,
  });

  final String uid;
  final String email;
  final String? displayName;
  final String role;

  bool get isAdmin => role == 'admin';

  factory AppUser.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return AppUser(
      uid: document.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String?,
      role: data['role'] as String? ?? 'user',
    );
  }
}
