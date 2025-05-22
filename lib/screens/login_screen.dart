import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _error = '';
  bool _loading = false;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      Navigator.pushReplacementNamed(context, '/connect');
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Error desconocido';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _register() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      Navigator.pushReplacementNamed(context, '/connect');
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Error desconocido';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() {
          _loading = false;
        });
        return; // Cancelado por el usuario
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      Navigator.pushReplacementNamed(context, '/connect');
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message ?? 'Error al iniciar sesión con Google';
      });
    } catch (e) {
      setState(() {
        _error = 'Error al iniciar sesión con Google: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _googleButton() {
    return ElevatedButton.icon(
      icon: Image.asset(
        'assets/google_logo.png',
        height: 24,
        width: 24,
      ),
      label: const Text('Iniciar sesión con Google'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        minimumSize: const Size(double.infinity, 48),
        side: const BorderSide(color: Colors.grey),
        textStyle: const TextStyle(fontSize: 16),
      ),
      onPressed: _loading ? null : _signInWithGoogle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('INICIO DE SESIÓN', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                  value != null && value.contains('@') ? null : 'Introduce un email válido',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  obscureText: true,
                  validator: (value) =>
                  value != null && value.length >= 6 ? null : 'Mínimo 6 caracteres',
                ),
                const SizedBox(height: 24),
                if (_error.isNotEmpty)
                  Text(_error, style: const TextStyle(color: Colors.red)),
                if (_loading)
                  const CircularProgressIndicator()
                else ...[
                  ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) _login();
                    },
                    child: const Text('Iniciar sesión'),
                  ),
                  TextButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) _register();
                    },
                    child: const Text('Crear cuenta'),
                  ),
                  const SizedBox(height: 10),
                  _googleButton(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}