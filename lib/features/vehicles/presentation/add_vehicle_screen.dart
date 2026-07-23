import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ocr/presentation/vin_scanner_screen.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  static final RegExp _vinPattern = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  final _formKey = GlobalKey<FormState>();
  final _vinController = TextEditingController();
  final _positionController = TextEditingController();

  bool _isSaving = false;
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void dispose() {
    _vinController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  String _normalizeVin(String value) => value.trim().toUpperCase();

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _errorMessage = 'Sesja wygasła. Zaloguj się ponownie.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final vin = _normalizeVin(_vinController.text);
    final position = _positionController.text.trim();
    final firestore = FirebaseFirestore.instance;
    final activeVehicles = firestore.collection('activeVehicles');
    final vehicleRef = activeVehicles.doc(vin);

    try {
      await firestore.runTransaction((transaction) async {
        final duplicate = await transaction.get(vehicleRef);
        if (duplicate.exists) {
          throw StateError('duplicate-vin');
        }

        final activeSnapshot = await activeVehicles.limit(100).get();
        if (activeSnapshot.docs.length >= 100) {
          throw StateError('active-limit');
        }

        transaction.set(vehicleRef, {
          'vin': vin,
          'position': position,
          'startedAt': FieldValue.serverTimestamp(),
          'createdBy': user.uid,
          'status': 'active',
          'warningMinutes': 35,
          'limitMinutes': 40,
        });
      });

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = switch (error.message) {
          'duplicate-vin' => 'Ten VIN jest już na liście aktywnych pojazdów.',
          'active-limit' => 'Osiągnięto limit 100 aktywnych pojazdów.',
          _ => 'Nie udało się zapisać pojazdu.',
        };
      });
    } on FirebaseException {
      if (mounted) {
        setState(() => _errorMessage = 'Nie udało się zapisać pojazdu.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openVinScanner() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final vin = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const VinScannerScreen()),
      );

      if (!mounted || vin == null) return;

      final normalizedVin = _normalizeVin(vin);
      _vinController.value = TextEditingValue(
        text: normalizedVin,
        selection: TextSelection.collapsed(offset: normalizedVin.length),
      );
      _formKey.currentState?.validate();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('VIN został odczytany z aparatu.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isSaving || _isScanning;

    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj pojazd')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _vinController,
                        maxLength: 17,
                        enabled: !isBusy,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            return newValue.copyWith(
                              text: newValue.text.toUpperCase(),
                              selection: newValue.selection,
                            );
                          }),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'VIN',
                          hintText: '17 znaków',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                        validator: (value) {
                          final vin = _normalizeVin(value ?? '');
                          if (vin.isEmpty) {
                            return 'Wpisz numer VIN.';
                          }
                          if (!_vinPattern.hasMatch(vin)) {
                            return 'VIN musi mieć 17 znaków i nie może zawierać I, O ani Q.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: isBusy ? null : _openVinScanner,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          _isScanning ? 'Otwieranie aparatu...' : 'Skanuj VIN aparatem',
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _positionController,
                        enabled: !isBusy,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _isSaving ? null : _saveVehicle(),
                        decoration: const InputDecoration(
                          labelText: 'Pozycja',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Wpisz pozycję pojazdu.';
                          }
                          return null;
                        },
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: isBusy ? null : _saveVehicle,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Dodaj i uruchom licznik'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
