import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';

void main() {
  runApp(const ProviderScope(child: WegaVinTimerApp()));
}

class WegaVinTimerApp extends StatelessWidget {
  const WegaVinTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WEGA VIN Timer',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), useMaterial3: true),
      routerConfig: createAppRouter(),
    );
  }
}
