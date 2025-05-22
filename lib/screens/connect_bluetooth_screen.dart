import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/material.dart';

class ConnectBluetoothScreen extends StatefulWidget {
  const ConnectBluetoothScreen({super.key});
  @override
  State<ConnectBluetoothScreen> createState() => _ConnectBluetoothScreenState();
}

class _ConnectBluetoothScreenState extends State<ConnectBluetoothScreen> {
  BluetoothDevice? obdDevice;
  BluetoothConnection? connection;
  String status = 'No conectado';

  @override
  void initState() {
    super.initState();
    _getPairedDevices();
  }

  Future<void> _getPairedDevices() async {
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
  }

  Future<void> _connect() async {
    if (obdDevice == null) {
      setState(() {
        status = 'No hay dispositivo OBD-II emparejado';
      });
      return;
    }
    setState(() {
      status = 'Conectando a ${obdDevice!.name}...';
    });
    try {
      connection = await BluetoothConnection.toAddress(obdDevice!.address);
      setState(() {
        status = 'Conectado a ${obdDevice!.name}';
      });
      // Aquí puedes enviar comandos AT o iniciar lectura periódica
    } catch (e) {
      setState(() {
        status = 'Error al conectar: $e';
      });
    }
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(status),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _connect,
              child: const Text('Conectar Bluetooth'),
            ),
            const SizedBox(height: 20),
            TextButton(
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