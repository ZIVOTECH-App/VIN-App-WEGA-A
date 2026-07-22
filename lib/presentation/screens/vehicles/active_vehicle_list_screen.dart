import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
import 'add_vin_screen.dart';

class ActiveVehicleListScreen extends StatelessWidget {
  const ActiveVehicleListScreen({super.key});
  static const routePath = '/vehicles';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Aktywne pojazdy'), actions: [
          IconButton(onPressed: () => context.go(HistoryScreen.routePath), icon: const Icon(Icons.history)),
          IconButton(onPressed: () => context.go(SettingsScreen.routePath), icon: const Icon(Icons.settings)),
        ]),
        body: const Center(child: Text('Lista aktywnych pojazdów zostanie zasilona lokalną bazą danych.')),
        floatingActionButton: FloatingActionButton.extended(onPressed: () => context.go(AddVinScreen.routePath), icon: const Icon(Icons.add), label: const Text('Dodaj VIN')),
      );
}
