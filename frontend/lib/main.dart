import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'l10n/app_messages.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_profile_screen.dart';
import 'services/panama_dpa_service.dart';
import 'services/reporter_profile_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();
  await PanamaDpaService.init();
  await AppMessages.load('es');
  final isConfigured = await ReporterProfileService.isProfileConfigured();

  runApp(AyudaLosSantosApp(initialScreen: isConfigured ? const HomeScreen() : const OnboardingProfileScreen()));
}

class AyudaLosSantosApp extends StatelessWidget {
  final Widget initialScreen;

  const AyudaLosSantosApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ayuda Panamá',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red.shade800,
          primary: Colors.red.shade800,
          secondary: Colors.amber.shade800,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.red.shade800,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: initialScreen,
    );
  }
}
