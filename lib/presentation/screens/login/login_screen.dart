import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../vehicles/active_vehicle_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  static const routePath = '/login';
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Logowanie operatora')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Imię lub identyfikator operatora')),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go(ActiveVehicleListScreen.routePath), child: const Text('Kontynuuj')),
          ]),
        ),
      );
}
