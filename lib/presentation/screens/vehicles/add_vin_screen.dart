import 'package:flutter/material.dart';

import '../../../core/validation/vin_validator.dart';

class AddVinScreen extends StatefulWidget {
  const AddVinScreen({super.key});
  static const routePath = '/vehicles/add';
  @override
  State<AddVinScreen> createState() => _AddVinScreenState();
}

class _AddVinScreenState extends State<AddVinScreen> {
  final _vinController = TextEditingController();
  bool _confirmed = false;
  @override
  void dispose() { _vinController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final validation = VinValidator.validate(_vinController.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Ręczne dodanie VIN')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _vinController, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'VIN', errorText: _vinController.text.isEmpty || validation.isValid ? null : validation.errorMessage), onChanged: (_) => setState(() {})),
          CheckboxListTile(value: _confirmed, onChanged: (value) => setState(() => _confirmed = value ?? false), title: const Text('Potwierdzam poprawność VIN przed zapisem')),
          FilledButton(onPressed: validation.isValid && _confirmed ? () {} : null, child: const Text('Zapisz pojazd')),
        ]),
      ),
    );
  }
}
