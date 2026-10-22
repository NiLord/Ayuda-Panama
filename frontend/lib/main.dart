import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'l10n/app_messages.dart';
import 'screens/home_screen.dart';
import 'services/panama_dpa_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.init();
  await PanamaDpaService.init();
  await AppMessages.load('es');

  runApp(const AyudaLosSantosApp());
}

class AyudaLosSantosApp extends StatelessWidget {
  final Widget initialScreen;

  const AyudaLosSantosApp({super.key, this.initialScreen = const HomeScreen()});

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
