import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  static const routePath = '/settings';
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Ustawienia')), body: const Center(child: Text('Ustawienia aplikacji.')));
}
