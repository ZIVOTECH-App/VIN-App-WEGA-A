import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  static const routePath = '/history';
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Historia')), body: const Center(child: Text('Historia zakończonych pojazdów.')));
}
