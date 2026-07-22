import 'package:flutter/material.dart';

class ActiveVehicleDetailScreen extends StatelessWidget {
  const ActiveVehicleDetailScreen({required this.vehicleId, super.key});
  static const routePath = '/vehicles/:id';
  final String vehicleId;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Szczegóły pojazdu')), body: Center(child: Text('Pojazd: $vehicleId')));
}
