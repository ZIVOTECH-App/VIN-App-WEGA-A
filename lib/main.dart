import 'dart:async';
import 'dart:io';


import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xls;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const WegaVinTimerApp());
}

String? _extractVin(String text) {
  final normalizedText = text
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), ' ');
  final matches = RegExp(r'[A-HJ-NPR-Z0-9]{17}').allMatches(normalizedText);

  for (final match in matches) {
    return match.group(0);
  }

  return null;
}

class WegaVinTimerApp extends StatelessWidget {
  const WegaVinTimerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WEGA VIN Timer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (!snapshot.hasData) {
            return const LoginScreen();
          }

          return const VinCheckScreen();
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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _message;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (_) {
      setState(() {
        _message = 'Nie udało się zalogować';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WEGA VIN Timer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'E-mail',
              ),
              keyboardType: TextInputType.emailAddress,
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
              onPressed: _isLoading ? null : _signIn,
              child: Text(_isLoading ? 'Logowanie...' : 'Zaloguj'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class VinCheckScreen extends StatefulWidget {
  const VinCheckScreen({super.key});

  @override
  State<VinCheckScreen> createState() => _VinCheckScreenState();
}

class _VinCheckScreenState extends State<VinCheckScreen> {
  static const int _maxVehicles = 100;
  static const Duration _timerDuration = Duration(minutes: 40);

  final TextEditingController _vinController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  Timer? _timer;
  String? _message;

  CollectionReference<Map<String, dynamic>> get _activeVehicles =>
      _firestore.collection('activeVehicles');

  CollectionReference<Map<String, dynamic>> get _history =>
      _firestore.collection('history');

  @override
  void initState() {
    super.initState();
    _startTimer();
    _saveMessagingToken();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _vinController.dispose();
    _positionController.dispose();
    _searchController.dispose();
    super.dispose();
  }


  String _normalizePosition(String position) {
    return position.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesSearch(Map<String, dynamic> data, String query) {
    if (query.isEmpty) {
      return true;
    }

    final vin = data['vinSearch'] as String? ??
        (data['vin'] as String? ?? '').toLowerCase();
    final position = data['positionSearch'] as String? ??
        (data['position'] as String? ?? '').toLowerCase();

    return vin.contains(query) || position.contains(query);
  }

  Future<void> _saveMessagingToken() async {
    final user = _auth.currentUser;

    if (user == null) {
      return;
    }

    final settings = await _messaging.requestPermission();

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    final token = await _messaging.getToken();

    if (token == null) {
      return;
    }

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('devices')
        .doc(token)
        .set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }


  Future<void> _scanVin() async {
    final vin = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VinScannerScreen()),
    );

    if (vin == null) {
      return;
    }

    _vinController.text = vin;
    setState(() {
      _message = 'Odczytany VIN: $vin';
    });
  }

  Future<void> _addVehicle() async {
    final vin = _vinController.text.trim().toUpperCase();
    final position = _normalizePosition(_positionController.text);
    final user = _auth.currentUser;
    final isValidVin = _extractVin(vin) == vin;

    if (user == null) {
      setState(() => _message = 'Zaloguj się ponownie');
      return;
    }

    if (!isValidVin) {
      setState(() => _message = 'VIN niepoprawny');
      return;
    }

    try {
      final activeCount = await _activeVehicles.count().get();

      if ((activeCount.count ?? 0) >= _maxVehicles) {
        throw const _VehicleException('Osiągnięto limit 100 pojazdów');
      }

      await _firestore.runTransaction((transaction) async {
        final activeSnapshot = await transaction.get(_activeVehicles.doc(vin));

        if (activeSnapshot.exists) {
          throw const _VehicleException('Ten VIN już istnieje');
        }

        transaction.set(_activeVehicles.doc(vin), {
          'vin': vin,
          'position': position,
          'vinSearch': vin.toLowerCase(),
          'positionSearch': position.toLowerCase(),
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
          'durationMinutes': _timerDuration.inMinutes,
          'fiveMinuteWarning': {
            'sendAfterMinutes': 35,
            'message': 'VIN: $vin — zostało 5 minut',
            'status': 'pending',
          },
        });
      });

      _vinController.clear();
      _positionController.clear();
      setState(() => _message = 'Pojazd dodany');
    } on _VehicleException catch (error) {
      setState(() => _message = error.message);
    } catch (_) {
      setState(() => _message = 'Nie udało się dodać pojazdu');
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _finishVehicle(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final user = _auth.currentUser;

    if (user == null) {
      setState(() => _message = 'Zaloguj się ponownie');
      return;
    }

    try {
      await _firestore.runTransaction((transaction) async {
        final activeDocument = await transaction.get(document.reference);

        if (!activeDocument.exists) {
          return;
        }

        final data = activeDocument.data()!;
        final startedAt = data['createdAt'] as Timestamp?;
        final actualDurationSeconds = _actualDurationSeconds(startedAt);
        final overtimeSeconds = actualDurationSeconds - _timerDuration.inSeconds;
        final status = actualDurationSeconds <= _timerDuration.inSeconds
            ? 'Zakończono w czasie'
            : 'Zakończono po czasie';

        transaction.set(_history.doc(), {
          'vin': data['vin'],
          'position': data['position'],
          'vinSearch': data['vinSearch'],
          'positionSearch': data['positionSearch'],
          'startedAt': startedAt,
          'endedAt': FieldValue.serverTimestamp(),
          'createdBy': data['createdBy'],
          'finishedBy': user.uid,
          'durationMinutes': _timerDuration.inMinutes,
          'actualDurationSeconds': actualDurationSeconds,
          'overtimeSeconds': overtimeSeconds < 0 ? 0 : overtimeSeconds,
          'status': status,
        });
        transaction.delete(document.reference);
      });
    } catch (_) {
      setState(() => _message = 'Nie udało się zakończyć procesu');
    }
  }

  int _actualDurationSeconds(Timestamp? startedAt) {
    if (startedAt == null) {
      return 0;
    }

    return DateTime.now().difference(startedAt.toDate()).inSeconds;
  }

  DateTime _plannedEnd(Timestamp? startedAt) {
    return (startedAt?.toDate() ?? DateTime.now()).add(_timerDuration);
  }

  String _remainingTime(Timestamp? startedAt) {
    if (startedAt == null) {
      return 'Oczekiwanie na czas serwera';
    }

    final remainingSeconds = _plannedEnd(startedAt)
        .difference(DateTime.now())
        .inSeconds;
    final isOvertime = remainingSeconds < 0;
    final absoluteSeconds = remainingSeconds.abs();
    final minutes = (absoluteSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (absoluteSeconds % 60).toString().padLeft(2, '0');

    return '${isOvertime ? '-' : ''}$minutes:$seconds';
  }

  String _formatDateTime(dynamic value) {
    if (value == null) {
      return 'Oczekiwanie na serwer';
    }

    final dateTime = value is Timestamp ? value.toDate() : value as DateTime;
    final date = dateTime.toLocal();
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute:$second';
  }

  String _formatDuration(Timestamp? startedAt, dynamic endedAt) {
    if (startedAt == null || endedAt == null) {
      return 'Oczekiwanie na serwer';
    }

    final endDate = endedAt is Timestamp
        ? endedAt.toDate()
        : endedAt as DateTime;
    final duration = endDate.difference(startedAt.toDate());
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return '$minutes:$seconds';
  }

  String _timeLabel(Timestamp? startedAt) {
    if (startedAt == null || _plannedEnd(startedAt).isAfter(DateTime.now())) {
      return 'Pozostały czas';
    }

    return 'Przekroczenie czasu';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WEGA VIN Timer'),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Wyloguj',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _vinController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Numer VIN',
                suffixIcon: IconButton(
                  onPressed: _scanVin,
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Skanuj VIN',
                ),
              ),
              maxLength: 17,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _positionController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Pozycja samochodu',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _addVehicle,
              child: const Text('Dodaj pojazd'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Szukaj VIN lub pozycji',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text(
              'Aktywne pojazdy',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _activeVehicles.orderBy('createdAt').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final query = _searchController.text.trim().toLowerCase();
                  final documents = snapshot.data!.docs
                      .where((document) => _matchesSearch(document.data(), query))
                      .toList();

                  return ListView.builder(
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      final document = documents[index];
                      final vehicle = document.data();
                      final startedAt = vehicle['createdAt'] as Timestamp?;

                      return Card(
                        child: ListTile(
                          title: Text(vehicle['vin'] as String),
                          subtitle: Text(
                            'Pozycja: ${vehicle['position']}\n'
                            '${_timeLabel(startedAt)}: '
                            '${_remainingTime(startedAt)}',
                          ),
                          isThreeLine: true,
                          trailing: TextButton(
                            onPressed: () => _finishVehicle(document),
                            child: const Text('Zakończ'),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _HistorySection(
              firestore: _firestore,
              auth: _auth,
              formatDateTime: _formatDateTime,
              formatDuration: _formatDuration,
            ),
          ],
        ),
      ),
    );
  }
}

class VinScannerScreen extends StatefulWidget {
  const VinScannerScreen({super.key});

  @override
  State<VinScannerScreen> createState() => _VinScannerScreenState();
}

class _VinScannerScreenState extends State<VinScannerScreen> {
  final TextRecognizer _textRecognizer = TextRecognizer();
  CameraController? _controller;
  String? _message;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() {
          _message = 'Nie znaleziono aparatu';
        });
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await controller.startImageStream(_processImage);

      if (!mounted) {
        return;
      }

      setState(() {
        _controller = controller;
        _message = 'Skieruj aparat na numer VIN';
      });
    } on CameraException catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _message = 'Brak zgody na aparat lub nie można go uruchomić';
      });
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isBusy || _controller == null || !mounted) {
      return;
    }

    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);

      if (inputImage == null) {
        return;
      }

      final recognizedText = await _textRecognizer.processImage(inputImage);
      final vin = _extractVin(recognizedText.text);

      if (vin == null) {
        setState(() {
          _message = 'Nie znaleziono poprawnego VIN';
        });
        return;
      }

      await _controller?.stopImageStream();

      if (mounted) {
        Navigator.of(context).pop(vin);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Nie udało się odczytać VIN';
        });
      }
    } finally {
      _isBusy = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;

    if (controller == null) {
      return null;
    }

    final rotation = InputImageRotationValue.fromRawValue(
      controller.description.sensorOrientation,
    );

    if (rotation == null) {
      return null;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    if (format == null) {
      return null;
    }

    final bytes = WriteBuffer();

    for (final plane in image.planes) {
      bytes.putUint8List(plane.bytes);
    }

    return InputImage.fromBytes(
      bytes: bytes.done().buffer.asUint8List(),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Skanuj VIN'),
      ),
      body: Column(
        children: [
          Expanded(
            child: controller == null || !controller.value.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : CameraPreview(controller),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _message ?? 'Uruchamianie aparatu...',
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Zamknij skaner'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatefulWidget {
  const _HistorySection({
    required this.firestore,
    required this.auth,
    required this.formatDateTime,
    required this.formatDuration,
  });

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final String Function(dynamic value) formatDateTime;
  final String Function(Timestamp? startedAt, dynamic endedAt) formatDuration;

  @override
  State<_HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends State<_HistorySection> {
  final TextEditingController _historySearchController = TextEditingController();
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _historySearchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Map<String, dynamic> data, String query) {
    if (query.isEmpty) {
      return true;
    }

    final vin = data['vinSearch'] as String? ??
        (data['vin'] as String? ?? '').toLowerCase();
    final position = data['positionSearch'] as String? ??
        (data['position'] as String? ?? '').toLowerCase();

    return vin.contains(query) || position.contains(query);
  }


  bool _matchesDateRange(Map<String, dynamic> data) {
    final endedAt = data['endedAt'];

    if (_dateRange == null || endedAt == null) {
      return true;
    }

    final endedDate = endedAt is Timestamp
        ? endedAt.toDate()
        : endedAt as DateTime;
    final endOfSelectedDay = DateTime(
      _dateRange!.end.year,
      _dateRange!.end.month,
      _dateRange!.end.day,
      23,
      59,
      59,
    );

    return !endedDate.isBefore(_dateRange!.start) &&
        !endedDate.isAfter(endOfSelectedDay);
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
    );

    if (selectedRange != null) {
      setState(() {
        _dateRange = selectedRange;
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _dateRange = null;
    });
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String _formatSeconds(dynamic value) {
    final totalSeconds = value is int ? value : 0;
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');

    return '$hours:$minutes:$seconds';
  }

  Future<void> _exportToExcel(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) async {
    final excel = xls.Excel.createExcel();
    final sheet = excel['Historia'];
    excel.delete('Sheet1');

    sheet.appendRow([
      xls.TextCellValue('VIN'),
      xls.TextCellValue('Miejsce'),
      xls.TextCellValue('Rozpoczęcie'),
      xls.TextCellValue('Zakończenie'),
      xls.TextCellValue('Rozpoczął'),
      xls.TextCellValue('Zakończył'),
      xls.TextCellValue('Rzeczywisty czas procesu'),
      xls.TextCellValue('Przekroczenie czasu'),
      xls.TextCellValue('Status'),
    ]);

    for (final document in documents) {
      final entry = document.data();
      sheet.appendRow([
        xls.TextCellValue(entry['vin'] as String? ?? ''),
        xls.TextCellValue(entry['position'] as String? ?? ''),
        xls.TextCellValue(widget.formatDateTime(entry['startedAt'])),
        xls.TextCellValue(widget.formatDateTime(entry['endedAt'])),
        xls.TextCellValue(entry['createdBy'] as String? ?? ''),
        xls.TextCellValue(entry['finishedBy'] as String? ?? ''),
        xls.TextCellValue(_formatSeconds(entry['actualDurationSeconds'])),
        xls.TextCellValue(_formatSeconds(entry['overtimeSeconds'])),
        xls.TextCellValue(entry['status'] as String? ?? ''),
      ]);
    }

    final bytes = excel.encode();

    if (bytes == null) {
      return;
    }

    final directory = await getTemporaryDirectory();
    final fileName = 'WEGA_VIN_Historia_${_formatDate(DateTime.now())}.xlsx';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Eksport historii WEGA VIN',
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser;

    if (user == null) {
      return const SizedBox.shrink();
    }

    return Expanded(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: widget.firestore.collection('users').doc(user.uid).snapshots(),
        builder: (context, userSnapshot) {
          final role = userSnapshot.data?.data()?['role'];

          if (role != 'admin') {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Historia',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text('Historia jest dostępna dla administratora.'),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Historia',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _historySearchController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Szukaj VIN lub pozycji',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _selectDateRange,
                      child: Text(
                        _dateRange == null
                            ? 'Wybierz zakres dat'
                            : '${_formatDate(_dateRange!.start)} - '
                                '${_formatDate(_dateRange!.end)}',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _dateRange == null ? null : _clearDateRange,
                    icon: const Icon(Icons.clear),
                    tooltip: 'Wyczyść zakres dat',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: widget.firestore
                      .collection('history')
                      .orderBy('endedAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final query = _historySearchController.text
                        .trim()
                        .toLowerCase();
                    final documents = snapshot.data!.docs
                        .where((document) => _matchesSearch(
                              document.data(),
                              query,
                            ))
                        .where((document) => _matchesDateRange(document.data()))
                        .toList();

                    return Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => _exportToExcel(documents),
                            icon: const Icon(Icons.download),
                            label: const Text('Eksportuj do Excel'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: documents.length,
                            itemBuilder: (context, index) {
                              final entry = documents[index].data();
                              final startedAt = entry['startedAt'] as Timestamp?;
                              final endedAt = entry['endedAt'];

                              return Card(
                                child: ListTile(
                                  title: Text(entry['vin'] as String),
                                  subtitle: Text(
                                    'Pozycja: ${entry['position']}\n'
                                    'Start: ${widget.formatDateTime(startedAt)}\n'
                                    'Koniec: ${widget.formatDateTime(endedAt)}\n'
                                    'Status: ${entry['status']}\n'
                                    'Utworzył: ${entry['createdBy']}\n'
                                    'Zakończył: ${entry['finishedBy']}\n'
                                    'Limit: ${entry['durationMinutes']} min\n'
                                    'Czas trwania: '
                                    '${widget.formatDuration(startedAt, endedAt)}\n'
                                    'Rzeczywisty czas (s): '
                                    '${entry['actualDurationSeconds']}\n'
                                    'Przekroczenie (s): '
                                    '${entry['overtimeSeconds']}',
                                  ),
                                  isThreeLine: false,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VehicleException implements Exception {
  const _VehicleException(this.message);

  final String message;
}
