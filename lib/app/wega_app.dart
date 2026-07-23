import 'package:flutter/material.dart';

import '../features/auth/presentation/auth_gate.dart';

class WegaApp extends StatelessWidget {
  const WegaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WEGA-A VIN Timer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E5AA8)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
