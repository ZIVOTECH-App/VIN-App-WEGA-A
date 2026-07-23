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

  Future<void> _onDestinationSelected(int index) async {
    if (index == 2) {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
      );
      if (mounted) {
        setState(() => _selectedIndex = 0);
      }
      return;
    }

    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
