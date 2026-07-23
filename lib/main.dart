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
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const _chargingMinutes = 30;
const _serviceMinutes = 40;
const _serviceWarningMinutes = 35;

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

final ValueNotifier<String?> _startupMessage = ValueNotifier<String?>(null);
final ValueNotifier<bool> _firebaseReady = ValueNotifier<bool>(false);

const AndroidNotificationChannel _vehicleOperationsChannel =
    AndroidNotificationChannel(
  'vehicle_operations',
  'Operacje pojazdów',
  description: 'Powiadomienia o zakończeniu ładowania i obsługi',
  importance: Importance.max,
  playSound: true,
);

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
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.local);
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await _notifications.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
  final androidNotifications = _notifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidNotifications?.createNotificationChannel(_vehicleOperationsChannel);
  await androidNotifications?.requestNotificationsPermission();
  await androidNotifications?.requestExactAlarmsPermission();
}

Future<void> _scheduleNotification(
  String title,
  String body,
  int id,
  DateTime scheduledAt,
) async {
  await _notifications.zonedSchedule(
    id,
    title,
    body,
    tz.TZDateTime.from(scheduledAt, tz.local),
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'vehicle_operations',
        'Operacje pojazdów',
        channelDescription: 'Powiadomienia o zakończeniu ładowania i obsługi',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        channelShowBadge: true,
      ),
      iOS: DarwinNotificationDetails(presentSound: true),
    ),
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
  );
}

Future<void> _cancelOperationNotifications(Map<String, dynamic> operation) async {
  await _notifications.cancel(
    operation['warningNotificationId'] as int? ??
        ((operation['id'] as String? ?? '').hashCode & 0x3fffffff) + 35,
  );
  await _notifications.cancel(
    operation['completionNotificationId'] as int? ??
        ((operation['id'] as String? ?? '').hashCode & 0x3fffffff) + 40,
  );
}

Future<void> _showNotification(String title, String body, int id) async {
  const android = AndroidNotificationDetails(
    'vehicle_operations',
    'Operacje pojazdów',
    channelDescription: 'Powiadomienia o zakończeniu ładowania i obsługi',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    channelShowBadge: true,
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

enum StepStage { location, scan, action }

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
  final List<Map<String, dynamic>> _operations = [];

  List<Map<String, dynamic>> get _activeOperations => _operations
      .where((operation) => operation['status'] == 'aktywna')
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _restoreOperations();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _connectivity =
        Connectivity().onConnectivityChanged.listen((_) => _syncPending());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _connectivity?.cancel();
    _locationController.dispose();
    _manualCodeController.dispose();
    super.dispose();
  }

  int _notificationId(String operationId, int suffix) =>
      (operationId.hashCode & 0x3fffffff) + suffix;

  int _operationNotificationId(Map<String, dynamic> operation, String field) =>
      operation[field] as int? ??
      _notificationId(
        operation['id'] as String? ?? '',
        field == 'warningNotificationId' ? 35 : 40,
      );

  void _tick() {
    if (!mounted || _activeOperations.isEmpty) return;
    final now = DateTime.now();
    var changed = false;
    for (final operation in _activeOperations) {
      final plannedEnd = DateTime.parse(operation['plannedEndAt'] as String);
      final type = operation['actionType'] as String;
      final warned = operation['warningSent'] == true;
      final finished = operation['completionNotified'] == true;
      if (type == 'obsługa' && !warned) {
        final warningAt = DateTime.parse(operation['startedAt'] as String)
            .add(const Duration(minutes: _serviceWarningMinutes));
        if (!now.isBefore(warningAt)) {
          unawaited(_showNotification(
            'Obsługa pojazdu',
            'Pozostało 5 minut do zakończenia obsługi.',
            _operationNotificationId(operation, 'warningNotificationId'),
          ));
          operation['warningSent'] = true;
          changed = true;
        }
      }
      if (!finished && !now.isBefore(plannedEnd)) {
        unawaited(_showNotification(
          type == 'ładowanie' ? 'Ładowanie zakończone' : 'Obsługa zakończona',
          type == 'ładowanie'
              ? 'Zakończono czas ładowania. Odłącz ładowarkę.'
              : 'Czas obsługi zakończony.',
          _operationNotificationId(operation, 'completionNotificationId'),
        ));
        operation['completionNotified'] = true;
        changed = true;
      }
    }
    if (changed) {
      unawaited(_persistOperations());
    }
    setState(() {});
  }

  Future<void> _restoreOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('activeOperations');
    if (raw != null) {
      final decoded = jsonDecode(raw) as List<dynamic>;
      setState(() {
        _operations
          ..clear()
          ..addAll(
            decoded.map((item) => Map<String, dynamic>.from(item as Map)),
          );
      });
    } else {
      final legacy = prefs.getString('activeOperation');
      if (legacy != null) {
        setState(() {
          _operations
            ..clear()
            ..add(Map<String, dynamic>.from(jsonDecode(legacy) as Map));
        });
        await prefs.remove('activeOperation');
        await _persistOperations();
      }
    }
    await _syncPending();
  }

  Future<void> _persistOperations() async {
    final prefs = await SharedPreferences.getInstance();
    if (_operations.isEmpty) {
      await prefs.remove('activeOperations');
    } else {
      await prefs.setString('activeOperations', jsonEncode(_operations));
    }
  }

  Future<void> _syncPending() async {
    var changed = false;
    for (final operation in List<Map<String, dynamic>>.from(_operations)) {
      if (operation['synced'] == true) continue;
      try {
        await _firestore
            .collection('operations')
            .doc(operation['id'] as String)
            .set(_firestorePayload(operation));
        operation['synced'] = true;
        changed = true;
        if (operation['status'] != 'aktywna') {
          _operations.removeWhere((item) => item['id'] == operation['id']);
        }
      } catch (_) {
        operation['synced'] = false;
      }
    }
    if (changed) {
      await _persistOperations();
      if (mounted) setState(() {});
    }
  }

  Map<String, dynamic> _firestorePayload(Map<String, dynamic> data) => {
        ...data,
        'startedAt':
            Timestamp.fromDate(DateTime.parse(data['startedAt'] as String)),
        'plannedEndAt':
            Timestamp.fromDate(DateTime.parse(data['plannedEndAt'] as String)),
        'actualEndAt': data['actualEndAt'] == null
            ? null
            : Timestamp.fromDate(DateTime.parse(data['actualEndAt'] as String)),
        'createdAt':
            Timestamp.fromDate(DateTime.parse(data['createdAt'] as String)),
        'updatedAt':
            Timestamp.fromDate(DateTime.parse(data['updatedAt'] as String)),
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
    final operationId = _firestore.collection('operations').doc().id;
    final operation = {
      'id': operationId,
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
      'warningNotificationId': _notificationId(operationId, 35),
      'completionNotificationId': _notificationId(operationId, 40),
      'warningSent': false,
      'completionNotified': false,
      'synced': false,
    };
    _operations.add(operation);
    await _scheduleOperationNotifications(operation);
    await _persistOperations();
    _resetForm(message: 'Operacja rozpoczęta. Możesz dodać kolejną.');
    await _syncPending();
  }

  Future<void> _scheduleOperationNotifications(
    Map<String, dynamic> operation,
  ) async {
    final type = operation['actionType'] as String;
    final startedAt = DateTime.parse(operation['startedAt'] as String);
    final plannedEnd = DateTime.parse(operation['plannedEndAt'] as String);
    if (type == 'obsługa') {
      await _scheduleNotification(
        'Obsługa pojazdu',
        'Pozostało 5 minut do zakończenia obsługi.',
        _operationNotificationId(operation, 'warningNotificationId'),
        startedAt.add(const Duration(minutes: _serviceWarningMinutes)),
      );
    }
    await _scheduleNotification(
      type == 'ładowanie' ? 'Ładowanie zakończone' : 'Obsługa zakończona',
      type == 'ładowanie'
          ? 'Zakończono czas ładowania. Odłącz ładowarkę.'
          : 'Czas obsługi zakończony.',
      _operationNotificationId(operation, 'completionNotificationId'),
      plannedEnd,
    );
  }

  Future<void> _finish(Map<String, dynamic> operation, String status) async {
    final now = DateTime.now();
    final startedAt = DateTime.parse(operation['startedAt'] as String);
    operation
      ..['actualEndAt'] = now.toIso8601String()
      ..['actualDurationSeconds'] = now.difference(startedAt).inSeconds
      ..['status'] = status
      ..['updatedAt'] = now.toIso8601String();
    await _cancelOperationNotifications(operation);
    try {
      await _firestore
          .collection('operations')
          .doc(operation['id'] as String)
          .set(_firestorePayload(operation));
      _operations.removeWhere((item) => item['id'] == operation['id']);
      await _persistOperations();
      setState(() => _message = 'Operacja zapisana w historii.');
    } catch (_) {
      operation['synced'] = false;
      await _persistOperations();
      setState(
        () => _message = 'Brak internetu. Operacja zostanie zsynchronizowana później.',
      );
    }
  }

  void _resetForm({String? message}) {
    setState(() {
      _stage = StepStage.location;
      _locationController.clear();
      _manualCodeController.clear();
      _code = null;
      _codeType = null;
      _message = message;
    });
  }

  String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _remaining(Map<String, dynamic> active) {
    final left =
        DateTime.parse(active['plannedEndAt'] as String).difference(DateTime.now());
    final seconds = left.inSeconds.abs();
    final sign = left.inSeconds < 0 ? '-' : '';
    return '$sign${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final activeOperations = _activeOperations;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_stage == StepStage.location) ...[
          Text(
            'Etap 1 — lokalizacja pojazdu',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Lokalizacja pojazdu',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _confirmLocation,
            child: const Text('Przejdź do skanowania'),
          ),
        ],
        if (_stage == StepStage.scan) ...[
          Text(
            'Etap 2 — skanowanie',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Lokalizacja: ${_locationController.text.trim()}'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scanCode,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Skanuj'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manualCodeController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Ręczny VIN lub identyfikator',
            ),
            onChanged: (_) => _manualCode(),
          ),
          if (_code != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Rodzaj kodu: $_codeType\nOdczytana wartość: $_code'),
            ),
          FilledButton(onPressed: _approveCode, child: const Text('Zatwierdź')),
        ],
        if (_stage == StepStage.action) ...[
          Text(
            'Etap 3 — wybór akcji',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Lokalizacja: ${_locationController.text.trim()}\nKod: $_code\nTyp: $_codeType',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _startAction('ładowanie'),
            child: const Text('Rozpocznij ładowanie (30 min)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _startAction('obsługa'),
            child: const Text('Rozpocznij obsługę (40 min)'),
          ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_message!, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 16),
        Text(
          'Aktywne operacje',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (activeOperations.isEmpty)
          const Text('Brak aktywnych operacji.')
        else
          ...activeOperations.map(_activeCard),
      ],
    );
  }

  Widget _activeCard(Map<String, dynamic> active) {
    final start = DateTime.parse(active['startedAt'] as String);
    final plannedEnd = DateTime.parse(active['plannedEndAt'] as String);
    final isOvertime = DateTime.now().isAfter(plannedEnd);
    final synced = active['synced'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Aktywna czynność', style: Theme.of(context).textTheme.titleLarge),
          Text('ID: ${active['id']}'),
          Text('Lokalizacja: ${active['vehicleLocation']}'),
          Text('Kod: ${active['scannedCode']} (${active['codeType']})'),
          Text('Czynność: ${active['actionType']}'),
          Text('Status: ${active['status']}'),
          Text('Start: ${_format(start)}'),
          Text('Planowany koniec: ${_format(plannedEnd)}'),
          Text('${isOvertime ? 'Przekroczony czas' : 'Pozostały czas'}: ${_remaining(active)}'),
          if (!synced) const Text('Tryb offline: zapis oczekuje na synchronizację.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _finish(active, 'zakończona wcześniej'),
            child: const Text('Zakończ wcześniej'),
          ),
          TextButton(
            onPressed: () => _finish(active, 'anulowana'),
            child: const Text('Anuluj'),
          ),
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

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode, BarcodeFormat.code128],
    returnImage: true,
  );
  final TextRecognizer _textRecognizer = TextRecognizer();
  DateTime _lastReadAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastReadValue;
  bool _isConfirming = false;
  bool _isProcessingText = false;

  static final RegExp _vinPattern = RegExp(r'[A-HJ-NPR-Z0-9]{17}');

  @override
  void dispose() {
    _controller.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  String _normalizeVin(String value) =>
      value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();

  String? _extractVin(String value) {
    final normalized = _normalizeVin(value);
    final directMatch = _vinPattern.firstMatch(normalized);
    if (directMatch != null) return directMatch.group(0);

    final joined = value
        .split(RegExp(r'\s+'))
        .map(_normalizeVin)
        .where((part) => part.isNotEmpty)
        .join();
    return _vinPattern.firstMatch(joined)?.group(0);
  }

  bool _isDuplicateRead(String value) {
    final now = DateTime.now();
    final duplicate = _lastReadValue == value &&
        now.difference(_lastReadAt) < const Duration(seconds: 3);
    _lastReadValue = value;
    _lastReadAt = now;
    return duplicate;
  }

  String _type(Barcode barcode, String value) {
    switch (barcode.format) {
      case BarcodeFormat.qrCode:
        return _extractVin(value) == value ? 'VIN z QR' : 'QR';
      case BarcodeFormat.code128:
        return _extractVin(value) == value
            ? 'VIN z Code 128 / GS1-128 / EAN-128'
            : 'Code 128 / GS1-128 / EAN-128';
      default:
        return _extractVin(value) == value ? 'VIN' : barcode.format.name;
    }
  }

  Future<void> _confirmRead(String value, String type) async {
    final normalized = _extractVin(value) ?? value.trim().toUpperCase();
    if (normalized.isEmpty || _isDuplicateRead(normalized) || _isConfirming) {
      return;
    }
    _isConfirming = true;
    await _controller.stop();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Odczytano: $normalized'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Skanuj ponownie'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Potwierdź'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      Navigator.of(context).pop(ScanResult(normalized, type));
      return;
    }
    _isConfirming = false;
    _lastReadValue = null;
    await _controller.start();
  }

  Future<void> _readText(BarcodeCapture capture) async {
    if (_isProcessingText || _isConfirming || capture.image == null) return;
    _isProcessingText = true;
    try {
      final size = MediaQuery.sizeOf(context);
      final inputImage = InputImage.fromBytes(
        bytes: capture.image!,
        metadata: InputImageMetadata(
          size: Size(size.width, size.height),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: size.width.toInt(),
        ),
      );
      final text = await _textRecognizer.processImage(inputImage);
      final vin = _extractVin(text.text);
      if (vin != null) {
        await _confirmRead(vin, 'VIN OCR');
      }
    } catch (_) {
      // OCR frames that cannot be decoded by ML Kit are ignored; barcode scanning continues.
    } finally {
      _isProcessingText = false;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        unawaited(_confirmRead(value, _type(barcode, value)));
        return;
      }
    }
    unawaited(_readText(capture));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Skanowanie')),
        body: Stack(children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Skieruj aparat na QR, Code 128, GS1-128, EAN-128 albo tekst VIN.',
                  ),
                ),
              ),
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
