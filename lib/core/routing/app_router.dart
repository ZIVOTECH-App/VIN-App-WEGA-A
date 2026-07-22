import 'package:go_router/go_router.dart';

import '../../presentation/screens/history/history_screen.dart';
import '../../presentation/screens/login/login_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/vehicles/add_vin_screen.dart';
import '../../presentation/screens/vehicles/active_vehicle_detail_screen.dart';
import '../../presentation/screens/vehicles/active_vehicle_list_screen.dart';

GoRouter createAppRouter() => GoRouter(
      initialLocation: LoginScreen.routePath,
      routes: [
        GoRoute(path: LoginScreen.routePath, builder: (context, state) => const LoginScreen()),
        GoRoute(path: ActiveVehicleListScreen.routePath, builder: (context, state) => const ActiveVehicleListScreen()),
        GoRoute(path: AddVinScreen.routePath, builder: (context, state) => const AddVinScreen()),
        GoRoute(
          path: ActiveVehicleDetailScreen.routePath,
          builder: (context, state) => ActiveVehicleDetailScreen(vehicleId: state.pathParameters['id']!),
        ),
        GoRoute(path: HistoryScreen.routePath, builder: (context, state) => const HistoryScreen()),
        GoRoute(path: SettingsScreen.routePath, builder: (context, state) => const SettingsScreen()),
      ],
    );
