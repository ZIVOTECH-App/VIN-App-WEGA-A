import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../use_cases/add_active_vehicle_use_case.dart';

final addActiveVehicleUseCaseProvider = Provider<AddActiveVehicleUseCase>((ref) => AddActiveVehicleUseCase());

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) => SharedPreferences.getInstance());
