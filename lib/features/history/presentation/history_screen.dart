import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum HistoryStatusFilter { all, onTime, late }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  HistoryStatusFilter _statusFilter = HistoryStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() => _query = _searchController.text.trim().toUpperCase());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyStream = FirebaseFirestore.instance
        .collection('history')
        .orderBy('endedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Historia pojazdów')),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: historyStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _HistoryMessage(
                icon: Icons.error_outline,
                title: 'Nie udało się pobrać historii',
                message: 'Sprawdź połączenie i uprawnienia Firestore.',
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allItems = snapshot.data?.docs ?? [];
            final visibleItems = allItems.where((document) {
              final data = document.data();
              final vin = (data['vin'] as String? ?? '').toUpperCase();
              final position = (data['position'] as String? ?? '').toUpperCase();
              final onTime = data['onTime'] as bool? ?? false;

              final matchesQuery = _query.isEmpty ||
                  vin.contains(_query) ||
                  position.contains(_query);
              final matchesStatus = switch (_statusFilter) {
                HistoryStatusFilter.all => true,
                HistoryStatusFilter.onTime => onTime,
                HistoryStatusFilter.late => !onTime,
              };

              return matchesQuery && matchesStatus;
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
                SegmentedButton<HistoryStatusFilter>(
                  segments: const [
                    ButtonSegment(
                      value: HistoryStatusFilter.all,
                      label: Text('Wszystkie'),
                      icon: Icon(Icons.list_alt),
                    ),
                    ButtonSegment(
                      value: HistoryStatusFilter.onTime,
                      label: Text('Na czas'),
                      icon: Icon(Icons.check_circle_outline),
                    ),
                    ButtonSegment(
                      value: HistoryStatusFilter.late,
                      label: Text('Po czasie'),
                      icon: Icon(Icons.warning_amber_outlined),
                    ),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (selection) {
                    setState(() => _statusFilter = selection.first);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Rekordy: ${allItems.length}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('Widoczne: ${visibleItems.length}'),
                  ],
                ),
                const SizedBox(height: 12),
                if (allItems.isEmpty)
                  const _HistoryMessage(
                    icon: Icons.history,
                    title: 'Historia jest pusta',
                    message: 'Zakończony pojazd pojawi się tutaj automatycznie.',
                  )
                else if (visibleItems.isEmpty)
                  const _HistoryMessage(
                    icon: Icons.search_off,
                    title: 'Brak wyników',
                    message: 'Zmień wyszukiwanie lub wybrany filtr.',
                  )
                else
                  ...visibleItems.map(
                    (document) => _HistoryCard(data: document.data()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final vin = data['vin'] as String? ?? 'Brak VIN';
    final position = data['position'] as String? ?? 'Brak pozycji';
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final endedAt = (data['endedAt'] as Timestamp?)?.toDate();
    final durationSeconds = data['durationSeconds'] as int? ?? 0;
    final onTime = data['onTime'] as bool? ?? false;
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = onTime ? colorScheme.primary : colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          onTime ? Icons.check_circle : Icons.error,
          color: statusColor,
        ),
        title: Text(vin),
        subtitle: Text('Pozycja: $position'),
        trailing: Text(
          _formatDuration(Duration(seconds: durationSeconds)),
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          _DetailRow(label: 'Rozpoczęto', value: _formatDateTime(startedAt)),
          _DetailRow(label: 'Zakończono', value: _formatDateTime(endedAt)),
          _DetailRow(
            label: 'Czas trwania',
            value: _formatDuration(Duration(seconds: durationSeconds)),
          ),
          _DetailRow(
            label: 'Status',
            value: onTime ? 'Zakończono na czas' : 'Przekroczono 40 minut',
            valueColor: statusColor,
          ),
          _DetailRow(
            label: 'Utworzył',
            value: data['createdBy'] as String? ?? 'Brak danych',
          ),
          _DetailRow(
            label: 'Zakończył',
            value: data['endedBy'] as String? ?? 'Brak danych',
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Brak danych';

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$day.$month.${value.year} $hour:$minute:$second';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
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
