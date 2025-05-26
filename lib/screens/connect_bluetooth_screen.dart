import 'dart:async';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

class ConnectBluetoothScreen extends StatefulWidget {
  const ConnectBluetoothScreen({super.key});
  @override
  State<ConnectBluetoothScreen> createState() => _ConnectBluetoothScreenState();
}

class _ConnectBluetoothScreenState extends State<ConnectBluetoothScreen> {
  BluetoothDevice? obdDevice;
  BluetoothConnection? connection;
  String status = 'No conectado';
  bool isConnecting = false;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
    _getPairedDevices();
  }

  Future<void> _checkBluetooth() async {
    // Solicita permisos necesarios
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (!(isEnabled ?? false)) {
      setState(() {
        status = 'Bluetooth desactivado. Actívalo y vuelve a intentarlo.';
        hasError = true;
      });
      return;
    }
  }

  Future<void> _getPairedDevices() async {
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        if (devices.isNotEmpty) {
          obdDevice = devices.firstWhere(
                (d) => d.name?.toUpperCase().contains('OBD') ?? false,
            orElse: () => devices.first,
          );
        } else {
          obdDevice = null;
        }
        if (obdDevice == null) status = 'Dispositivo OBD-II no emparejado';
      });
    } catch (e) {
      setState(() {
        status = 'Error al buscar dispositivos: $e';
        hasError = true;
      });
    }
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  Future<void> _connect() async {
    if (obdDevice == null) {
      setState(() {
        status = 'No hay dispositivo OBD-II emparejado';
        hasError = true;
      });
      return;
    }
    setState(() {
      status = 'Conectando a ${obdDevice!.name}...';
      isConnecting = true;
      hasError = false;
    });
    try {
      connection = await BluetoothConnection.toAddress(obdDevice!.address)
          .timeout(const Duration(seconds: 8));
      setState(() {
        status = 'Conectado a ${obdDevice!.name}';
        isConnecting = false;
        hasError = false;
      });
      // Aquí puedes enviar comandos AT o iniciar lectura periódica
    } on TimeoutException {
      setState(() {
        status = 'Tiempo de espera agotado. ¿El OBD-II está encendido y cerca?';
        isConnecting = false;
        hasError = true;
      });
      _showErrorDialog('No se pudo conectar en el tiempo esperado.\n'
          'Verifica que el OBD-II esté encendido, cerca y emparejado.');
    } catch (e) {
      setState(() {
        status = 'No se pudo conectar. Asegúrate de que el OBD-II está encendido, emparejado y sin otras apps conectadas.';
        isConnecting = false;
        hasError = true;
      });
      _showErrorDialog(
          'No se pudo conectar con el OBD-II.\n\n'
              'Verifica lo siguiente:\n'
              '- El OBD-II está encendido y conectado al coche\n'
              '- Está emparejado en los ajustes de Bluetooth\n'
              '- No hay otras apps conectadas al OBD-II\n'
              '- El Bluetooth del móvil está activado'
      );
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Problema de conexión'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                hasError = false;
              });
            },
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _connect();
            },
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1976D2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar Bluetooth'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(
                'Menú',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesión'),
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasError
                  ? Icons.error_outline
                  : (connection?.isConnected ?? false)
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: hasError
                  ? Colors.red
                  : (connection?.isConnected ?? false)
                  ? Colors.green
                  : azul,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasError ? Colors.red : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            if (isConnecting)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: azul.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: azul,
                  textStyle: const TextStyle(fontSize: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isConnecting ? null : _connect,
                child: const Text('Conectar Bluetooth'),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: azul,
                textStyle: const TextStyle(fontSize: 16),
              ),
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/monitor');
              },
              child: const Text('Saltar (Skip)'),
            ),
          ],
        ),
      ),
    );
  }
}
