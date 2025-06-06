import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/connect_bluetooth_screen.dart';
import 'screens/diagnosis_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const OBDApp());
}

class OBDApp extends StatelessWidget {
  const OBDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OBD-II Car',
      initialRoute: '/',
      routes: {
        '/': (context) => AuthGate(),
        '/connect': (context) => const ConnectBluetoothScreen(),
        '/diagnosis': (context) => const DiagnosisScreen(),
      },
        theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF001F51),
        onPrimary: Color(0xFF001F51),
        secondary: Color(0xFFFFFFFF),
        onSecondary: Color(0xFF151515),
        background: Color(0xFFFFFFFF),
        onBackground: Color(0xFF1C1C1C),
        error: Color(0xFFBA1A1A),
        onError: Color(0xFFFF0000),
        surface: Color(0xFFFAFDFB),
        onSurface: Color(0xFF191C1B),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) {
            return const LoginScreen();
          } else {
            return const ConnectBluetoothScreen();
          }
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
