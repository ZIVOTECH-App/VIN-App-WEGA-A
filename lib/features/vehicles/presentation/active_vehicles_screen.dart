import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'add_vehicle_screen.dart';

class ActiveVehiclesScreen extends StatefulWidget {
  const ActiveVehiclesScreen({super.key});

  @override
  State<ActiveVehiclesScreen> createState() => _ActiveVehiclesScreenState();
}

class _ActiveVehiclesScreenState extends State<ActiveVehiclesScreen> {
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onSearchChanged() {
    setState(() => _query = _searchController.text.trim().toUpperCase());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  Future<void> _openAddVehicle() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddVehicleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesStream = FirebaseFirestore.instance
        .collection('activeVehicles')
        .orderBy('startedAt', descending: false)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aktywne pojazdy'),
        actions: [
          IconButton(
            tooltip: 'Wyloguj',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: vehiclesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _MessageView(
                icon: Icons.error_outline,
                title: 'Nie udało się pobrać pojazdów',
                message: 'Sprawdź połączenie i uprawnienia Firestore.',
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allVehicles = snapshot.data?.docs ?? [];
            final filteredVehicles = allVehicles.where((document) {
              if (_query.isEmpty) return true;
              final data = document.data();
              final vin = (data['vin'] as String? ?? '').toUpperCase();
              final position = (data['position'] as String? ?? '').toUpperCase();
              return vin.contains(_query) || position.contains(_query);
            }).toList();

            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Szukaj po VIN lub pozycji',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Wyczyść',
                            onPressed: _searchController.clear,
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Aktywne: ${allVehicles.length}/100',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_query.isNotEmpty)
                      Text('Wyniki: ${filteredVehicles.length}'),
                  ],
                ),
                const SizedBox(height: 12),
                if (allVehicles.isEmpty)
                  const _MessageView(
                    icon: Icons.directions_car_outlined,
                    title: 'Brak aktywnych pojazdów',
                    message: 'Dodaj pierwszy pojazd, aby uruchomić licznik 40 minut.',
                  )
                else if (filteredVehicles.isEmpty)
                  const _MessageView(
                    icon: Icons.search_off,
                    title: 'Brak wyników',
                    message: 'Nie znaleziono pojazdu pasującego do wyszukiwania.',
                  )
                else
                  ...filteredVehicles.map(
                    (document) => _VehicleCard(data: document.data()),
                  ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddVehicle,
        icon: const Icon(Icons.add),
        label: const Text('Dodaj pojazd'),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final vin = data['vin'] as String? ?? 'Brak VIN';
    final position = data['position'] as String? ?? 'Brak pozycji';
    final timestamp = data['startedAt'] as Timestamp?;
    final startedAt = timestamp?.toDate();
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt).isNegative
            ? Duration.zero
            : DateTime.now().difference(startedAt);

    final elapsedMinutes = elapsed.inMinutes;
    final isAlarm = elapsedMinutes >= 40;
    final isWarning = elapsedMinutes >= 35;
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isAlarm
        ? colorScheme.error
        : isWarning
            ? colorScheme.tertiary
            : colorScheme.primary;
    final statusText = isAlarm
        ? 'Przekroczono 40 minut'
        : isWarning
            ? 'Zbliża się limit'
            : 'W trakcie';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.directions_car, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    vin,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _formatDuration(elapsed),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Pozycja: $position'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 18, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
