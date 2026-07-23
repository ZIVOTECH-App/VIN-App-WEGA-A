import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:excel/excel.dart' as xls;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _chargingMinutes = 30;
const _serviceMinutes = 40;
const _serviceWarningMinutes = 35;

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

final ValueNotifier<String?> _startupMessage = ValueNotifier<String?>(null);
final ValueNotifier<bool> _firebaseReady = ValueNotifier<bool>(false);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WegaVehicleApp());
  unawaited(_initializeAppServices());
}

Future<void> _initializeAppServices() async {
  try {
    await Firebase.initializeApp();
    _firebaseReady.value = true;
  } catch (error) {
    _startupMessage.value =
        'Firebase nie jest skonfigurowane. Logowanie jest chwilowo niedostępne.';
    return;
  }

  try {
    await _initializeNotifications();
  } catch (error) {
    _startupMessage.value =
        'Nie udało się uruchomić lokalnych powiadomień. Pozostałe funkcje aplikacji są dostępne.';
  }
}

Future<void> _initializeNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await _notifications.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
  await _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
}

Future<void> _showNotification(String title, String body, int id) async {
  const android = AndroidNotificationDetails(
    'vehicle_operations',
    'Operacje pojazdów',
    channelDescription: 'Powiadomienia o zakończeniu ładowania i obsługi',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
  );
  const ios = DarwinNotificationDetails(presentSound: true);
  await _notifications.show(
    id,
    title,
    body,
    const NotificationDetails(android: android, iOS: ios),
  );
}

class WegaVehicleApp extends StatelessWidget {
  const WegaVehicleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WEGA Obsługa Pojazdów',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: ValueListenableBuilder<bool>(
        valueListenable: _firebaseReady,
        builder: (context, firebaseReady, _) {
          if (!firebaseReady) {
            return const LoginScreen();
          }
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return snapshot.hasData ? const HomeScreen() : const LoginScreen();
            },
          );
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _message;
  bool _loading = false;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      if (!_firebaseReady.value) {
        setState(
          () => _message = _startupMessage.value ??
              'Trwa inicjalizacja Firebase. Spróbuj ponownie za chwilę.',
        );
        return;
      }
      final login = _loginController.text.trim();
      final email = login.contains('@') ? login : '$login@wega.local';
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (_) {
      setState(() => _message = 'Błędny e-mail/nazwa użytkownika lub hasło.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Logowanie')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-mail lub nazwa użytkownika',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Hasło',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _signIn,
              child: Text(_loading ? 'Logowanie...' : 'Zaloguj'),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _startupMessage,
              builder: (context, message, _) {
                if (message == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(message, textAlign: TextAlign.center),
                );
              },
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const {};
        final role = data['role'] as String? ?? 'user';
        final username = data['username'] as String? ?? user.email ?? user.uid;
        return DefaultTabController(
          length: role == 'admin' ? 2 : 1,
          child: Scaffold(
            appBar: AppBar(
              title: Text('WEGA - $username'),
              bottom: TabBar(
                tabs: [
                  const Tab(text: 'Obsługa'),
                  if (role == 'admin') const Tab(text: 'Historia'),
                ],
              ),
              actions: [
                IconButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  tooltip: 'Wyloguj',
                ),
              ],
            ),
            body: TabBarView(
              children: [
                OperationScreen(role: role, username: username),
                if (role == 'admin') HistoryScreen(username: username),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum StepStage { location, scan, action, active }

class OperationScreen extends StatefulWidget {
  const OperationScreen({super.key, required this.role, required this.username});

  final String role;
  final String username;

  @override
  State<OperationScreen> createState() => _OperationScreenState();
}

class _OperationScreenState extends State<OperationScreen> {
  final _locationController = TextEditingController();
  final _manualCodeController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Timer? _ticker;
  StreamSubscription<List<ConnectivityResult>>? _connectivity;
  StepStage _stage = StepStage.location;
  String? _message;
  String? _code;
  String? _codeType;
  Map<String, dynamic>? _active;
  String? _activeId;
  bool _synced = true;

  @override
  void initState() {
    super.initState();
    _restoreActiveOperation();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _connectivity = Connectivity().onConnectivityChanged.listen((_) => _syncPending());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _connectivity?.cancel();
    _locationController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  void _tick() {
    final active = _active;
    if (active == null || !mounted) return;
    final now = DateTime.now();
    final plannedEnd = DateTime.parse(active['plannedEndAt'] as String);
    final type = active['actionType'] as String;
    final warned = active['warningSent'] == true;
    final finished = active['completionNotified'] == true;
    if (type == 'obsługa' && !warned) {
      final warningAt = DateTime.parse(active['startedAt'] as String)
          .add(const Duration(minutes: _serviceWarningMinutes));
      if (!now.isBefore(warningAt)) {
        _showNotification('Obsługa pojazdu', 'Pozostało 5 minut do zakończenia obsługi.', 35);
        active['warningSent'] = true;
        _persistActive();
      }
    }
    if (!finished && !now.isBefore(plannedEnd)) {
      _showNotification(
        type == 'ładowanie' ? 'Ładowanie zakończone' : 'Obsługa zakończona',
        type == 'ładowanie'
            ? 'Zakończono czas ładowania. Odłącz ładowarkę.'
            : 'Czas obsługi zakończony.',
        40,
      );
      active['completionNotified'] = true;
      _persistActive();
    }
    setState(() {});
  }

  Future<void> _restoreActiveOperation() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('activeOperation');
    if (raw != null) {
      setState(() {
        _active = jsonDecode(raw) as Map<String, dynamic>;
        _activeId = _active!['id'] as String?;
        _synced = _active!['synced'] == true;
        _stage = StepStage.active;
      });
    }
    await _syncPending();
  }

  Future<void> _persistActive() async {
    final prefs = await SharedPreferences.getInstance();
    if (_active == null) {
      await prefs.remove('activeOperation');
    } else {
      await prefs.setString('activeOperation', jsonEncode(_active));
    }
  }

  Future<void> _syncPending() async {
    if (_active == null || _active!['synced'] == true) return;
    try {
      await _firestore.collection('operations').doc(_activeId).set(_firestorePayload(_active!));
      _active!['synced'] = true;
      _synced = true;
      await _persistActive();
      if (mounted) setState(() {});
    } catch (_) {
      _synced = false;
    }
  }

  Map<String, dynamic> _firestorePayload(Map<String, dynamic> data) => {
        ...data,
        'startedAt': Timestamp.fromDate(DateTime.parse(data['startedAt'] as String)),
        'plannedEndAt': Timestamp.fromDate(DateTime.parse(data['plannedEndAt'] as String)),
        'actualEndAt': data['actualEndAt'] == null
            ? null
            : Timestamp.fromDate(DateTime.parse(data['actualEndAt'] as String)),
        'createdAt': Timestamp.fromDate(DateTime.parse(data['createdAt'] as String)),
        'updatedAt': Timestamp.fromDate(DateTime.parse(data['updatedAt'] as String)),
      };

  void _confirmLocation() {
    if (_locationController.text.trim().isEmpty) {
      setState(() => _message = 'Lokalizacja pojazdu jest obowiązkowa.');
      return;
    }
    setState(() {
      _message = null;
      _stage = StepStage.scan;
    });
  }

  Future<void> _scanCode() async {
    final result = await Navigator.of(context).push<ScanResult>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result != null) {
      setState(() {
        _code = result.value;
        _codeType = result.type;
        _manualCodeController.text = result.value;
        _message = null;
      });
    }
  }

  void _manualCode() {
    final value = _manualCodeController.text.trim().toUpperCase();
    if (value.isEmpty) return;
    setState(() {
      _code = value;
      _codeType = value.length == 17 ? 'VIN / wpis ręczny' : 'Wpis ręczny';
    });
  }

  void _approveCode() {
    _manualCode();
    if (_code == null || _code!.isEmpty) {
      setState(() => _message = 'Zeskanuj albo wpisz identyfikator.');
      return;
    }
    setState(() => _stage = StepStage.action);
  }

  Future<void> _startAction(String type) async {
    final user = _auth.currentUser!;
    final now = DateTime.now();
    final minutes = type == 'ładowanie' ? _chargingMinutes : _serviceMinutes;
    _activeId = _firestore.collection('operations').doc().id;
    _active = {
      'id': _activeId,
      'userId': user.uid,
      'username': widget.username,
      'userRole': widget.role,
      'vehicleLocation': _locationController.text.trim(),
      'scannedCode': _code,
      'codeType': _codeType,
      'actionType': type,
      'plannedDurationMinutes': minutes,
      'startedAt': now.toIso8601String(),
      'plannedEndAt': now.add(Duration(minutes: minutes)).toIso8601String(),
      'actualEndAt': null,
      'status': 'aktywna',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'warningSent': false,
      'completionNotified': false,
      'synced': false,
    };
    await _persistActive();
    setState(() {
      _stage = StepStage.active;
      _synced = false;
    });
    await _syncPending();
  }

  Future<void> _finish(String status) async {
    if (_active == null) return;
    final now = DateTime.now();
    final startedAt = DateTime.parse(_active!['startedAt'] as String);
    _active!
      ..['actualEndAt'] = now.toIso8601String()
      ..['actualDurationSeconds'] = now.difference(startedAt).inSeconds
      ..['status'] = status
      ..['updatedAt'] = now.toIso8601String();
    try {
      await _firestore.collection('operations').doc(_activeId).set(_firestorePayload(_active!));
      await _persistActive();
      await SharedPreferences.getInstance().then((p) => p.remove('activeOperation'));
      _reset(message: 'Operacja zapisana w historii.');
    } catch (_) {
      _active!['synced'] = false;
      await _persistActive();
      setState(() => _message = 'Brak internetu. Operacja zostanie zsynchronizowana później.');
    }
  }

  void _reset({String? message}) {
    setState(() {
      _stage = StepStage.location;
      _locationController.clear();
      _manualCodeController.clear();
      _code = null;
      _codeType = null;
      _active = null;
      _activeId = null;
      _message = message;
    });
  }

  String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _remaining(Map<String, dynamic> active) {
    final left = DateTime.parse(active['plannedEndAt'] as String).difference(DateTime.now());
    final seconds = left.inSeconds.abs();
    final sign = left.inSeconds < 0 ? '-' : '';
    return '$sign${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_stage == StepStage.location) ...[
          Text('Etap 1 — lokalizacja pojazdu', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Lokalizacja pojazdu'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _confirmLocation, child: const Text('Przejdź do skanowania')),
        ],
        if (_stage == StepStage.scan) ...[
          Text('Etap 2 — skanowanie', style: Theme.of(context).textTheme.titleLarge),
          Text('Lokalizacja: ${_locationController.text.trim()}'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _scanCode, icon: const Icon(Icons.qr_code_scanner), label: const Text('Skanuj QR / Code 128 / GS1-128')),
          const SizedBox(height: 12),
          TextField(
            controller: _manualCodeController,
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Ręczny VIN lub identyfikator'),
            onChanged: (_) => _manualCode(),
          ),
          if (_code != null) Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Rodzaj kodu: $_codeType\nOdczytana wartość: $_code'),
          ),
          FilledButton(onPressed: _approveCode, child: const Text('Zatwierdź')),
        ],
        if (_stage == StepStage.action) ...[
          Text('Etap 3 — wybór akcji', style: Theme.of(context).textTheme.titleLarge),
          Text('Lokalizacja: ${_locationController.text.trim()}\nKod: $_code\nTyp: $_codeType'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _startAction('ładowanie'), child: const Text('Rozpocznij ładowanie (30 min)')),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => _startAction('obsługa'), child: const Text('Rozpocznij obsługę (40 min)')),
        ],
        if (_stage == StepStage.active && _active != null) _activeCard(_active!),
        if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, textAlign: TextAlign.center)),
      ],
    );
  }

  Widget _activeCard(Map<String, dynamic> active) {
    final start = DateTime.parse(active['startedAt'] as String);
    final plannedEnd = DateTime.parse(active['plannedEndAt'] as String);
    final isOvertime = DateTime.now().isAfter(plannedEnd);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Aktywna czynność', style: Theme.of(context).textTheme.titleLarge),
          Text('Lokalizacja: ${active['vehicleLocation']}'),
          Text('Kod: ${active['scannedCode']} (${active['codeType']})'),
          Text('Czynność: ${active['actionType']}'),
          Text('Start: ${_format(start)}'),
          Text('Planowany koniec: ${_format(plannedEnd)}'),
          Text('${isOvertime ? 'Przekroczony czas' : 'Pozostały czas'}: ${_remaining(active)}'),
          if (!_synced) const Text('Tryb offline: zapis oczekuje na synchronizację.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => _finish('zakończona wcześniej'), child: const Text('Zakończ wcześniej')),
          TextButton(onPressed: () => _finish('anulowana'), child: const Text('Anuluj')),
        ]),
      ),
    );
  }
}

class ScanResult {
  const ScanResult(this.value, this.type);
  final String value;
  final String type;
}

class ScannerScreen extends StatelessWidget {
  const ScannerScreen({super.key});

  String _type(Barcode barcode) {
    switch (barcode.format) {
      case BarcodeFormat.qrCode:
        return 'QR';
      case BarcodeFormat.code128:
        return 'Code 128 / GS1-128 / EAN-128';
      default:
        return barcode.rawValue?.length == 17 ? 'VIN' : barcode.format.name;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Skanowanie kodu')),
        body: Stack(children: [
          MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.trim().isNotEmpty) {
                  Navigator.of(context).pop(ScanResult(value.trim().toUpperCase(), _type(barcode)));
                  break;
                }
              }
            },
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Skieruj aparat na QR, VIN, Code 128 lub GS1-128.'))),
            ),
          ),
        ]),
      );
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.username});
  final String username;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _userFilter = TextEditingController();
  final _locationFilter = TextEditingController();
  final _codeFilter = TextEditingController();
  String? _actionFilter;
  String? _statusFilter;
  DateTimeRange? _range;

  @override
  void dispose() {
    _userFilter.dispose();
    _locationFilter.dispose();
    _codeFilter.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> e) {
    bool contains(String field, TextEditingController c) =>
        c.text.trim().isEmpty || (e[field] as String? ?? '').toLowerCase().contains(c.text.trim().toLowerCase());
    final startedAt = e['startedAt'];
    final start = startedAt is Timestamp ? startedAt.toDate() : null;
    final inRange = _range == null || start == null ||
        (!start.isBefore(_range!.start) && start.isBefore(_range!.end.add(const Duration(days: 1))));
    return contains('username', _userFilter) &&
        contains('vehicleLocation', _locationFilter) &&
        contains('scannedCode', _codeFilter) &&
        (_actionFilter == null || e['actionType'] == _actionFilter) &&
        (_statusFilter == null || e['status'] == _statusFilter) &&
        inRange;
  }

  String _fmt(dynamic v) {
    if (v == null) return '-';
    final d = (v as Timestamp).toDate().toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _dateName() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _export(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final excel = xls.Excel.createExcel();
    final sheet = excel['Historia'];
    excel.delete('Sheet1');
    sheet.appendRow(['Data', 'Start', 'Koniec', 'Użytkownik', 'Lokalizacja', 'Kod', 'Typ kodu', 'Czynność', 'Plan', 'Rzeczywisty czas', 'Status'].map(xls.TextCellValue.new).toList());
    for (final d in docs) {
      final e = d.data();
      final start = e['startedAt'] as Timestamp?;
      final end = e['actualEndAt'] as Timestamp?;
      sheet.appendRow([
        start == null ? '' : _fmt(start).split(' ').first,
        _fmt(start),
        _fmt(end),
        e['username'] ?? '',
        e['vehicleLocation'] ?? '',
        e['scannedCode'] ?? '',
        e['codeType'] ?? '',
        e['actionType'] ?? '',
        '${e['plannedDurationMinutes'] ?? ''} min',
        '${e['actualDurationSeconds'] ?? ''} s',
        e['status'] ?? '',
      ].map((v) => xls.TextCellValue(v.toString())).toList());
    }
    final bytes = excel.encode();
    if (bytes == null) return;
    final file = File('${(await getTemporaryDirectory()).path}/historia_operacji_${_dateName()}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Eksport historii operacji');
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('operations').orderBy('startedAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs.where((d) => _matches(d.data())).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                SizedBox(width: 180, child: TextField(controller: _userFilter, decoration: const InputDecoration(labelText: 'Użytkownik'), onChanged: (_) => setState(() {}))),
                SizedBox(width: 180, child: TextField(controller: _locationFilter, decoration: const InputDecoration(labelText: 'Lokalizacja'), onChanged: (_) => setState(() {}))),
                SizedBox(width: 180, child: TextField(controller: _codeFilter, decoration: const InputDecoration(labelText: 'Kod'), onChanged: (_) => setState(() {}))),
                DropdownButton<String?>(value: _actionFilter, hint: const Text('Czynność'), items: const [DropdownMenuItem(value: null, child: Text('Wszystkie')), DropdownMenuItem(value: 'ładowanie', child: Text('Ładowanie')), DropdownMenuItem(value: 'obsługa', child: Text('Obsługa'))], onChanged: (v) => setState(() => _actionFilter = v)),
                DropdownButton<String?>(value: _statusFilter, hint: const Text('Status'), items: const [DropdownMenuItem(value: null, child: Text('Wszystkie')), DropdownMenuItem(value: 'aktywna', child: Text('aktywna')), DropdownMenuItem(value: 'zakończona', child: Text('zakończona')), DropdownMenuItem(value: 'zakończona wcześniej', child: Text('zakończona wcześniej')), DropdownMenuItem(value: 'anulowana', child: Text('anulowana')), DropdownMenuItem(value: 'przekroczony czas', child: Text('przekroczony czas'))], onChanged: (v) => setState(() => _statusFilter = v)),
                OutlinedButton(onPressed: () async { final now = DateTime.now(); final r = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 1)); if (r != null) setState(() => _range = r); }, child: const Text('Data od-do')),
                FilledButton.icon(onPressed: () => _export(docs), icon: const Icon(Icons.download), label: const Text('Eksport Excel')),
              ]),
            ),
            Expanded(child: ListView.builder(itemCount: docs.length, itemBuilder: (context, i) {
              final e = docs[i].data();
              return Card(child: ListTile(
                title: Text('${e['scannedCode']} — ${e['actionType']}'),
                subtitle: Text('Data: ${_fmt(e['startedAt']).split(' ').first}\nStart: ${_fmt(e['startedAt'])}\nKoniec: ${_fmt(e['actualEndAt'])}\nUżytkownik: ${e['username']}\nLokalizacja: ${e['vehicleLocation']}\nTyp kodu: ${e['codeType']}\nPlan: ${e['plannedDurationMinutes']} min\nRzeczywisty czas: ${e['actualDurationSeconds'] ?? '-'} s\nStatus: ${e['status']}'),
                isThreeLine: false,
              ));
            })),
          ]);
        },
      );
}
