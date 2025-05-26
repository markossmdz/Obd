import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:proytecto_fin_de_curso/screens/viajes_screen.dart';


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
  double? nivelCombustible;
  int lecturas = 0;
  int sumaVelocidad = 0;
  double sumaConsumo = 0;
  static const double capacidadDeposito = 50.0;
  final _buffer = StringBuffer();

  @override
  void initState() {
    super.initState();
    if (MonitorScreen.connection != null && MonitorScreen.connection!.isConnected) {
      _initializeOBD();
    }
  }

  void _initializeOBD() async {
    await _sendOBDCommand('ATZ');
    await _sendOBDCommand('ATSP0');
    startReadingOBD();
  }

  void startReadingOBD() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _readMultipleData();
    });
  }

  Future<void> _readMultipleData() async {
    await Future.wait([
      _readRPM(),
      _readVelocidad(),
      _readTempMotor(),
      _readNivelCombustible(),
      _readConsumoMedio(),
      _readConsumoInstantaneo(),
    ]);
    _calcularValoresMedios();
    _calcularKmHechos();
    _calcularKmRestantes();
  }

  Future<void> _readRPM() async => _processCommand('010C', (data) {
    rpm = ((data[2] << 8) + data[3]) ~/ 4;
  });

  Future<void> _readVelocidad() async => _processCommand('010D', (data) {
    velocidad = data[2];
    sumaVelocidad += data[2];
    lecturas++;
  });

  Future<void> _readTempMotor() async => _processCommand('0105', (data) {
    tempMotor = data[2] - 40;
  });

  Future<void> _readNivelCombustible() async => _processCommand('012F', (data) {
    nivelCombustible = (data[2] / 255) * 100;
  });

  Future<void> _readConsumoMedio() async => _processCommand('015E', (data) {
    consumoMedio = ((data[2] << 8) + data[3]) / 20;
  });

  Future<void> _readConsumoInstantaneo() async => _processCommand('0165', (data) {
    if (data.length >= 4) {
      consumoInst = ((data[2] << 8) + data[3]) / 100.0;
    }
  });

  Future<void> _processCommand(String command, Function(List<int>) processor) async {
    try {
      final response = await _sendOBDCommand(command);
      if (response.isNotEmpty) {
        if (response.contains('NO DATA')) {
          // Opcional: Muestra mensaje de "no soportado"
          // Puedes actualizar un estado específico para ese dato
          return;
        }
        final cleanData = _cleanResponse(response);
        if (cleanData.length >= 3) {
          processor(cleanData);
        }
      }
    } catch (e) {
      print('Error en $command: ${e.toString()}');
      // Opcional: setState para indicar error en la UI
    }
  }

  List<int> _cleanResponse(String response) {
    return response
        .replaceAll(RegExp(r'[^0-9A-F ]'), '')
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => int.parse(s, radix: 16))
        .toList();
  }

  Future<String> _sendOBDCommand(String command) async {
    if (MonitorScreen.connection == null || !MonitorScreen.connection!.isConnected) {
      throw Exception('No hay conexión Bluetooth');
    }

    final completer = Completer<String>();
    final subscription = MonitorScreen.connection!.input!.listen((data) {
      _buffer.write(ascii.decode(data));
      if (_buffer.toString().contains('>')) {
        completer.complete(_buffer.toString());
        _buffer.clear();
      }
    });

    MonitorScreen.connection!.output.add(utf8.encode('$command\r'));
    await MonitorScreen.connection!.output.allSent;

    return completer.future.timeout(const Duration(seconds: 2), onTimeout: () {
      subscription.cancel();
      _buffer.clear();
      throw TimeoutException('Tiempo de espera agotado para: $command');
    });
  }

  void _calcularValoresMedios() {
    velocidadMedia = lecturas > 0 ? sumaVelocidad / lecturas : 0;
  }

  void _calcularKmHechos() {
    if (velocidad != null) {
      final horas = 2 / 3600;
      kmHechos = (kmHechos! + (velocidad! * horas)).round();
    }
  }

  void _calcularKmRestantes() {
    if (nivelCombustible != null && consumoMedio != null && velocidadMedia != null) {
      final litrosDisponibles = capacidadDeposito * (nivelCombustible! / 100);
      kmRestantes = (litrosDisponibles / consumoMedio! * velocidadMedia!).round();
    }
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    MonitorScreen.connection?.dispose();
    super.dispose();
  }

  Widget _buildInfoCard(String title, String value, {IconData? icon}) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 30, color: Colors.blue),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 18)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoreo OBD-II'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth),
            tooltip: 'Pantalla Bluetooth',
            onPressed: () => Navigator.pushNamed(context, '/connect'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeOBD,
            tooltip: 'Reiniciar conexión',
          ),
          IconButton(
            icon: const Icon(Icons.medical_services),
            onPressed: () => Navigator.pushNamed(context, '/diagnosis'),
            tooltip: 'Pantalla de diagnóstico',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Menú',
                style: TextStyle(color: Colors.white, fontSize: 24),
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
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                children: [
                  _buildInfoCard('RPM', rpm?.toString() ?? '---', icon: Icons.speed),
                  _buildInfoCard('Velocidad', '${velocidad ?? '---'} km/h', icon: Icons.speed),
                  _buildInfoCard('Temp. Motor', '${tempMotor ?? '---'}°C', icon: Icons.thermostat),
                  _buildInfoCard('Combustible', nivelCombustible != null
                      ? '${nivelCombustible!.toStringAsFixed(1)}%'
                      : '---', icon: Icons.local_gas_station),
                  _buildInfoCard('Consumo Inst.', consumoInst != null
                      ? '${consumoInst!.toStringAsFixed(1)} L/h'
                      : '---', icon: Icons.speed),
                  _buildInfoCard('Consumo Medio', consumoMedio != null
                      ? '${consumoMedio!.toStringAsFixed(1)} L/h'
                      : '---', icon: Icons.bar_chart),
                  _buildInfoCard('Km Recorridos', '${kmHechos ?? '---'} km', icon: Icons.directions_car),
                  _buildInfoCard('Autonomía', '${kmRestantes ?? '---'} km', icon: Icons.map),
                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50), // botón ancho y alto decente
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TripRecordingScreen(connection: MonitorScreen.connection),
                  ),
                );
              },
              child: const Text('Iniciar viaje', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),

          ],
        ),
      ),
    );
  }
}
