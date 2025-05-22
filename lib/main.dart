import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/connect_bluetooth_screen.dart';
import 'screens/monitor_screen.dart';
import 'screens/diagnosis_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(OBDApp());
}

class OBDApp extends StatelessWidget {
  const OBDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OBD-II Car',
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/connect': (context) => const ConnectBluetoothScreen(),
        '/monitor': (context) => const MonitorScreen(),
        '/diagnosis': (context) => const DiagnosisScreen(),
      },
    );
  }
}