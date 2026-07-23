import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdministrationScreen extends StatelessWidget {
  const AdministrationScreen({super.key});

  Future<void> _changeRole(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> userDocument,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final data = userDocument.data();
    final currentRole = data['role'] as String? ?? 'user';
    String selectedRole = currentRole;

    final newRole = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Zmień rolę użytkownika'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: 'user',
                groupValue: selectedRole,
                title: const Text('Użytkownik'),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedRole = value);
                  }
                },
              ),
              RadioListTile<String>(
                value: 'admin',
                groupValue: selectedRole,
                title: const Text('Administrator'),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedRole = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: currentUser?.uid == userDocument.id && selectedRole != 'admin'
                  ? null
                  : () => Navigator.of(dialogContext).pop(selectedRole),
              child: const Text('Zapisz'),
            ),
          ],
        ),
      ),
    );

    if (newRole == null || newRole == currentRole) return;

    try {
      await userDocument.reference.update({
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rola użytkownika została zaktualizowana.')),
        );
      }
    } on FirebaseException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nie udało się zmienić roli użytkownika.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('email')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Administracja')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nie udało się pobrać użytkowników.'),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = snapshot.data?.docs ?? [];
            if (users.isEmpty) {
              return const Center(child: Text('Brak użytkowników.'));
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final document = users[index];
                final data = document.data();
                final email = data['email'] as String? ?? 'Brak adresu e-mail';
                final displayName = data['displayName'] as String?;
                final role = data['role'] as String? ?? 'user';
                final isAdmin = role == 'admin';

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Icon(isAdmin ? Icons.admin_panel_settings : Icons.person),
                    ),
                    title: Text(
                      displayName == null || displayName.trim().isEmpty
                          ? email
                          : displayName,
                    ),
                    subtitle: Text(
                      displayName == null || displayName.trim().isEmpty
                          ? (isAdmin ? 'Administrator' : 'Użytkownik')
                          : '$email\n${isAdmin ? 'Administrator' : 'Użytkownik'}',
                    ),
                    isThreeLine: displayName != null && displayName.trim().isNotEmpty,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changeRole(context, document),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
