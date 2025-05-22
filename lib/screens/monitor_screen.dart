import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';


class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});
  static BluetoothConnection? connection;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  Timer? _timer;
  int? rpm;
  int? velocidad;
  int? tempMotor;
  double? consumoInst;
  double? consumoMedio;
  double? velocidadMedia;
  int? kmHechos = 0;
  int? kmRestantes = 0;
  double? nivelCombustible; // en %
  String log = '';
  int lecturas = 0;
  int sumaVelocidad = 0;
  int sumaConsumo = 0;
  static const double capacidadDeposito = 50.0; // litros, ajústalo a tu coche

  @override
  void initState() {
    super.initState();
    if (MonitorScreen.connection != null && MonitorScreen.connection!.isConnected) {
      startReadingOBD();
    }
  }

  @override
  void dispose() {
    stopReadingOBD();
    super.dispose();
  }

  void startReadingOBD() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await readRPM();
      await readVelocidad();
      await readTempMotor();
      await readNivelCombustible();
      await readConsumoMedio();
      calcularValoresMedios();
      calcularKmHechos();
      calcularKmRestantes();
    });
  }

  void stopReadingOBD() {
    _timer?.cancel();
  }

  Future<void> readRPM() async {
    await _sendOBDCommand('010C', (response) {
      final parts = response.split(' ');
      if (parts.length >= 4) {
        int xx = int.tryParse(parts[2], radix: 16) ?? 0;
        int yy = int.tryParse(parts[3], radix: 16) ?? 0;
        setState(() {
          rpm = ((xx * 256) + yy) ~/ 4;
          log = 'RPM: $rpm\n$log';
        });
      }
    });
  }

  Future<void> readVelocidad() async {
    await _sendOBDCommand('010D', (response) {
      final parts = response.split(' ');
      if (parts.length >= 3) {
        int xx = int.tryParse(parts[2], radix: 16) ?? 0;
        setState(() {
          velocidad = xx;
          sumaVelocidad += xx;
          lecturas++;
          log = 'Velocidad: $velocidad km/h\n$log';
        });
      }
    });
  }

  Future<void> readTempMotor() async {
    await _sendOBDCommand('0105', (response) {
      final parts = response.split(' ');
      if (parts.length >= 3) {
        int xx = int.tryParse(parts[2], radix: 16) ?? 0;
        setState(() {
          tempMotor = xx - 40;
          log = 'Temp Motor: $tempMotor °C\n$log';
        });
      }
    });
  }

  Future<void> readNivelCombustible() async {
    // PID 2F: nivel de combustible en %
    await _sendOBDCommand('012F', (response) {
      final parts = response.split(' ');
      if (parts.length >= 3) {
        int xx = int.tryParse(parts[2], radix: 16) ?? 0;
        double fuelLevel = xx * 100 / 255;
        setState(() {
          nivelCombustible = fuelLevel;
          consumoInst = fuelLevel; // puedes mostrarlo como % o estimar autonomía
        });
      }
    });
  }

  Future<void> readConsumoMedio() async {
    // PID 5E: Engine Fuel Rate (L/h)
    await _sendOBDCommand('015E', (response) {
      final parts = response.split(' ');
      if (parts.length >= 4) {
        int xx = int.tryParse(parts[2], radix: 16) ?? 0;
        int yy = int.tryParse(parts[3], radix: 16) ?? 0;
        double fuelRate = ((xx * 256) + yy) / 20.0; // L/h
        setState(() {
          consumoMedio = fuelRate;
        });
      }
    });
  }

  void calcularValoresMedios() {
    setState(() {
      velocidadMedia = (lecturas > 0 && sumaVelocidad > 0) ? sumaVelocidad / lecturas : null;
    });
  }

  void calcularKmHechos() {
    // Cada lectura es cada 2 segundos; distancia = velocidad * tiempo
    // velocidad en km/h, tiempo en horas (2/3600)
    if (velocidad != null) {
      double distancia = velocidad! * (2 / 3600);
      setState(() {
        kmHechos = (kmHechos ?? 0) + distancia.round();
      });
    }
  }

  void calcularKmRestantes() {
    // Estimación: kmRestantes = (nivelCombustible% * capacidadDeposito) / consumoMedio * 100
    if (nivelCombustible != null && consumoMedio != null && consumoMedio! > 0) {
      double litrosRestantes = capacidadDeposito * (nivelCombustible! / 100);
      // Consumo medio en L/h, velocidad media en km/h
      // Autonomía = litrosRestantes / (consumoMedio / velocidadMedia)
      double autonomia = velocidadMedia != null && velocidadMedia! > 0
          ? litrosRestantes / (consumoMedio! / velocidadMedia!)
          : 0;
      setState(() {
        kmRestantes = autonomia.round();
      });
    }
  }

  Future<void> _sendOBDCommand(String command, Function(String) onResponse) async {
    final connection = MonitorScreen.connection;
    if (connection != null && connection.isConnected) {
      connection.output.add(utf8.encode('$command\r'));
      await connection.output.allSent;
      await for (Uint8List data in connection.input!) {
        String response = ascii.decode(data);
        if (response.contains(command.replaceAll('01', '41'))) {
          onResponse(response);
          break;
        }
      }
    }
  }

  Widget _buildInfoCard(String title, String value, {IconData? icon}) {
    return Expanded(
      child: Card(
        child: SizedBox(
          height: 60,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) Icon(icon, size: 28),
                if (icon != null) const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(value, style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    const azul = Color(0xFF1976D2);

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushNamed(context, '/connect'); // Ajusta la ruta si tu pantalla se llama diferente
            },
          ),
          title: const Text('Monitoreo')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                _buildInfoCard('RPM', rpm?.toString() ?? '-', icon: Icons.speed),
                _buildInfoCard('Temp. Motor', tempMotor != null ? '$tempMotor°C' : '-', icon: Icons.thermostat),
              ],
            ),
            Row(
              children: [
                _buildInfoCard('Combustible', nivelCombustible != null ? '${nivelCombustible!.toStringAsFixed(1)} %' : '-', icon: Icons.local_gas_station),
                _buildInfoCard('Consumo Medio', consumoMedio != null ? '${consumoMedio!.toStringAsFixed(1)} L/h' : '-', icon: Icons.show_chart),
              ],
            ),
            Row(
              children: [
                _buildInfoCard('Velocidad', velocidad?.toString() ?? '-', icon: Icons.directions_car),
                _buildInfoCard('Vel. Media', velocidadMedia != null ? '${velocidadMedia!.toStringAsFixed(1)} km/h' : '-', icon: Icons.speed_outlined),
              ],
            ),
            Row(
              children: [
                _buildInfoCard('Km hechos', kmHechos?.toString() ?? '-', icon: Icons.av_timer),
                _buildInfoCard('Km para repostar', kmRestantes?.toString() ?? '-', icon: Icons.ev_station),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: azul,
                textStyle: const TextStyle(fontSize: 16),
              ),
              onPressed: () {
                Navigator.pushNamed(context, '/diagnosis');
              },
              child: const Text('Diagnosis de Fallos'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Text(log),
              ),
            ),
          ],
        ),
      ),
    );
  }
}