import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../features/history/presentation/history_screen.dart';
import '../features/vehicles/presentation/active_vehicles_screen.dart';
import '../features/vehicles/presentation/add_vehicle_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const _pages = <Widget>[
    ActiveVehiclesScreen(),
    HistoryScreen(),
  ];

  static const _titles = <String>[
    'Aktywne pojazdy',
    'Historia pojazdów',
  ];

  Future<void> _onDestinationSelected(int index) async {
    if (index == 2) {
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
      );

      if (mounted && added == true) {
        setState(() => _selectedIndex = 0);
      }
      return;
    }

    setState(() => _selectedIndex = index);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Wyloguj',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: 'Aktywne',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Historia',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Dodaj',
          ),
        ],
      ),
    );
  }
}
