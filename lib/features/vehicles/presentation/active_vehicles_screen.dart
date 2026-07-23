import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ActiveVehiclesScreen extends StatefulWidget {
  const ActiveVehiclesScreen({super.key});

  @override
  State<ActiveVehiclesScreen> createState() => _ActiveVehiclesScreenState();
}

class _ActiveVehiclesScreenState extends State<ActiveVehiclesScreen> {
  final _searchController = TextEditingController();
  final Set<String> _finishingVehicleIds = <String>{};
  Timer? _refreshTimer;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
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

  Future<void> _finishVehicle(
    QueryDocumentSnapshot<Map<String, dynamic>> vehicle,
  ) async {
    if (_finishingVehicleIds.contains(vehicle.id)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Sesja wygasła. Zaloguj się ponownie.');
      return;
    }

    setState(() => _finishingVehicleIds.add(vehicle.id));

    final firestore = FirebaseFirestore.instance;
    final activeRef = firestore.collection('activeVehicles').doc(vehicle.id);
    final historyRef = firestore.collection('history').doc();

    try {
      await firestore.runTransaction((transaction) async {
        final activeSnapshot = await transaction.get(activeRef);
        if (!activeSnapshot.exists) {
          throw StateError('vehicle-not-found');
        }

        final data = activeSnapshot.data()!;
        final startedTimestamp = data['startedAt'] as Timestamp?;
        if (startedTimestamp == null) {
          throw StateError('missing-start-time');
        }

        final startedAt = startedTimestamp.toDate();
        final endedAt = DateTime.now();
        final duration = endedAt.difference(startedAt);
        final durationSeconds = duration.isNegative ? 0 : duration.inSeconds;
        final limitMinutes = data['limitMinutes'] as int? ?? 40;

        transaction.set(historyRef, {
          ...data,
          'activeVehicleId': activeSnapshot.id,
          'startedAt': startedTimestamp,
          'endedAt': Timestamp.fromDate(endedAt),
          'durationSeconds': durationSeconds,
          'durationMinutes': durationSeconds ~/ 60,
          'onTime': durationSeconds <= limitMinutes * 60,
          'status': 'completed',
          'endedBy': user.uid,
        });
        transaction.delete(activeRef);
      });

      if (mounted) {
        _showMessage('Pojazd został zakończony i przeniesiony do historii.');
      }
    } on StateError catch (error) {
      if (!mounted) return;
      final message = switch (error.message) {
        'vehicle-not-found' => 'Pojazd nie jest już aktywny.',
        'missing-start-time' => 'Brakuje czasu rozpoczęcia pojazdu.',
        _ => 'Nie udało się zakończyć pojazdu.',
      };
      _showMessage(message);
    } on FirebaseException {
      if (mounted) {
        _showMessage('Nie udało się zakończyć pojazdu. Sprawdź uprawnienia.');
      }
    } finally {
      if (mounted) {
        setState(() => _finishingVehicleIds.remove(vehicle.id));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesStream = FirebaseFirestore.instance
        .collection('activeVehicles')
        .orderBy('startedAt', descending: false)
        .snapshots();

    return SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: vehiclesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _MessageView(
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
            final position =
                (data['position'] as String? ?? '').toUpperCase();
            return vin.contains(_query) || position.contains(_query);
          }).toList();

          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
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
                  message:
                      'Użyj zakładki Dodaj, aby uruchomić licznik 40 minut.',
                )
              else if (filteredVehicles.isEmpty)
                const _MessageView(
                  icon: Icons.search_off,
                  title: 'Brak wyników',
                  message:
                      'Nie znaleziono pojazdu pasującego do wyszukiwania.',
                )
              else
                ...filteredVehicles.map(
                  (document) => _VehicleCard(
                    vehicle: document,
                    isFinishing: _finishingVehicleIds.contains(document.id),
                    onFinish: () => _finishVehicle(document),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.vehicle,
    required this.isFinishing,
    required this.onFinish,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> vehicle;
  final bool isFinishing;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final data = vehicle.data();
    final vin = data['vin'] as String? ?? 'Brak VIN';
    final position = data['position'] as String? ?? 'Brak pozycji';
    final timestamp = data['startedAt'] as Timestamp?;
    final startedAt = timestamp?.toDate();
    final elapsed = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt).isNegative
            ? Duration.zero
            : DateTime.now().difference(startedAt);

    final limitMinutes = data['limitMinutes'] as int? ?? 40;
    final warningMinutes = limitMinutes > 5 ? limitMinutes - 5 : limitMinutes;
    final elapsedMinutes = elapsed.inMinutes;
    final isAlarm = elapsedMinutes >= limitMinutes;
    final isWarning = elapsedMinutes >= warningMinutes;
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = isAlarm
        ? colorScheme.error
        : isWarning
            ? colorScheme.tertiary
            : colorScheme.primary;
    final statusText = isAlarm
        ? 'Przekroczono $limitMinutes minut'
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
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isFinishing ? null : onFinish,
                icon: isFinishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(isFinishing ? 'Kończenie...' : 'Zakończ'),
                ),
              ),
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
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
