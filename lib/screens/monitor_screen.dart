import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'diagnosis_screen.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({Key? key, this.connection}) : super(key: key);

  final BluetoothConnection? connection;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  Timer? _timer;
  int? rpm;
  int? velocidad;
  int? tempMotor;
  int? presionAdmision;
  int? tempAireAdmision;
  double? maf;
  double? consumoInst;
  String? error;
  bool isLoading = true;

  // Buffer y cola para la gestión de respuestas
  List<int> _inputBuffer = [];
  final List<Completer<String>> _responseQueue = [];
  StreamSubscription? _inputSubscription;

  bool get isDemoMode => widget.connection == null;

  @override
  void initState() {
    super.initState();
    if (!isDemoMode && widget.connection!.isConnected) {
      _startListening(widget.connection!);
      _initializeOBD();
    } else {
      // Si no hay conexión, quitar la animación de carga
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inputSubscription?.cancel();
    widget.connection?.dispose();
    super.dispose();
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
  }

  void _initializeOBD() async {
    setState(() {
      error = null;
      isLoading = true;
    });
    try {
      await _sendObdCommand('ATZ');
      await _sendObdCommand('ATE0');
      await _sendObdCommand('ATL0');
      await _sendObdCommand('ATS0');
      await _sendObdCommand('ATSP0');
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
        await _readObdData();
      });
    } catch (e) {
      setState(() {
        error = 'Error inicializando OBD-II: $e';
        isLoading = false;
      });
    }
  }

  void _startListening(BluetoothConnection connection) {
    _inputSubscription?.cancel();
    _inputBuffer.clear();
    _inputSubscription = connection.input!.listen((data) {
      _inputBuffer.addAll(data);
      String bufferStr = String.fromCharCodes(_inputBuffer);
      if (bufferStr.contains('>')) {
        final response = bufferStr.substring(0, bufferStr.indexOf('>') + 1);
        _inputBuffer = _inputBuffer.sublist(bufferStr.indexOf('>') + 1);
        if (_responseQueue.isNotEmpty) {
          _responseQueue.removeAt(0).complete(response);
        }
      }
    });
  }

  Future<String> _sendObdCommand(String command) async {
    if (widget.connection == null || !widget.connection!.isConnected) {
      throw Exception('No hay conexión Bluetooth');
    }
    final completer = Completer<String>();
    _responseQueue.add(completer);

    widget.connection!.output.add(utf8.encode('$command\r'));
    await widget.connection!.output.allSent;

    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      if (_responseQueue.contains(completer)) {
        _responseQueue.remove(completer);
      }
      throw TimeoutException('Timeout esperando respuesta OBD');
    });
  }

  Future<void> _readObdData() async {
    try {
      final rpmResponse = await _sendObdCommand('010C');
      rpm = _extractRpm(rpmResponse);

      final speedResponse = await _sendObdCommand('010D');
      velocidad = _extractSpeed(speedResponse);

      final tempResponse = await _sendObdCommand('0105');
      tempMotor = _extractTemp(tempResponse);

      final presionAdmisionResponse = await _sendObdCommand('010B');
      presionAdmision = _extractPresionAdmision(presionAdmisionResponse);

      final tempAireResponse = await _sendObdCommand('010F');
      tempAireAdmision = _extractTempAireAdmision(tempAireResponse);

      final mafResponse = await _sendObdCommand('0110');
      maf = _extractMaf(mafResponse);

      consumoInst = _calcularConsumoInstantaneo(maf, velocidad);

      // Cuando al menos uno de estos datos esté disponible, quitamos la animación
      if (rpm != null || velocidad != null || tempMotor != null) {
        setState(() {
          isLoading = false;
          error = null;
        });
      } else {
        setState(() {
          isLoading = true;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error leyendo datos: $e';
        isLoading = false;
      });
    }
  }

  int? _extractRpm(String response) {
    String clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    int idx = clean.indexOf('410C');
    if (idx != -1 && clean.length >= idx + 8) {
      String data = clean.substring(idx + 4, idx + 8);
      int A = int.parse(data.substring(0, 2), radix: 16);
      int B = int.parse(data.substring(2, 4), radix: 16);
      return ((A * 256) + B) ~/ 4;
    }
    return null;
  }

  int? _extractSpeed(String response) {
    String clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    int idx = clean.indexOf('410D');
    if (idx != -1 && clean.length >= idx + 6) {
      String data = clean.substring(idx + 4, idx + 6);
      return int.parse(data, radix: 16);
    }
    return null;
  }

  int? _extractTemp(String response) {
    String clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    int idx = clean.indexOf('4105');
    if (idx != -1 && clean.length >= idx + 6) {
      String data = clean.substring(idx + 4, idx + 6);
      return int.parse(data, radix: 16) - 40;
    }
    return null;
  }

  int? _extractPresionAdmision(String response) {
    String clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    int idx = clean.indexOf('410B');
    if (idx != -1 && clean.length >= idx + 6) {
      String data = clean.substring(idx + 4, idx + 6);
      return int.parse(data, radix: 16);
    }
    return null;
  }

  int? _extractTempAireAdmision(String response) {
    String clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    int idx = clean.indexOf('410F');
    if (idx != -1 && clean.length >= idx + 6) {
      String data = clean.substring(idx + 4, idx + 6);
      return int.parse(data, radix: 16) - 40;
    }
    return null;
  }

  double? _extractMaf(String response) {
    String clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    int idx = clean.indexOf('4110');
    if (idx != -1 && clean.length >= idx + 8) {
      String data = clean.substring(idx + 4, idx + 8);
      int A = int.parse(data.substring(0, 2), radix: 16);
      int B = int.parse(data.substring(2, 4), radix: 16);
      return ((A * 256) + B) / 100.0; // MAF en g/s
    }
    return null;
  }

  /// Cálculo del consumo instantáneo en L/100km usando MAF y velocidad
  double? _calcularConsumoInstantaneo(double? maf, int? velocidad) {
    if (maf == null || velocidad == null || velocidad == 0) return null;
    // Fórmula estándar para gasolina:
    // L/100km = (MAF * 0.08206 * 3600) / (velocidad * 0.74)
    // MAF en g/s, velocidad en km/h
    return (maf * 0.08206 * 3600) / (velocidad * 0.74*100);
  }

  Widget _buildInfoCard(String title, String value, {IconData? icon}) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 30, color: Colors.blue),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
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
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF001823),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(12.0),
          ),
        ),
        title: const Text('Datos en tiempo real'),
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
            onPressed: isDemoMode ? null : _initializeOBD,
            tooltip: 'Reiniciar conexión',
          ),
        ],
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
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            if (isDemoMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Modo demo: sin conexión Bluetooth activa.',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 1,
                childAspectRatio: 3,
                children: [
                  _buildInfoCard('RPM', isDemoMode ? '---' : (rpm?.toString() ?? '---'), icon: Icons.speed),
                  _buildInfoCard('Velocidad', isDemoMode ? '---' : ('${velocidad ?? '---'} km/h'), icon: Icons.speed),
                  _buildInfoCard('Consumo inst.', isDemoMode ? '---' : (consumoInst != null && consumoInst!.isFinite ? '${consumoInst!.toStringAsFixed(2)} L/100km' : 'En ralentí'), icon: Icons.local_gas_station),
                  _buildInfoCard('Temp. Motor', isDemoMode ? '---' : ('${tempMotor ?? '---'}°C'), icon: Icons.thermostat),
                  _buildInfoCard('Presión admisión', isDemoMode ? '---' : (presionAdmision != null ? '$presionAdmision kPa' : '---'), icon: Icons.compress),
                  _buildInfoCard('Temp. aire admisión', isDemoMode ? '---' : (tempAireAdmision != null ? '$tempAireAdmision°C' : '---'), icon: Icons.air),
                  _buildInfoCard('Flujo de Masa de Aire', isDemoMode ? '---' : (maf != null ? '${maf!.toStringAsFixed(2)} g/s' : '---'), icon: Icons.cloud),

                ],
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DiagnosisScreen(connection: widget.connection),
                  ),
                );
              },
              child: const Text('Diagnosis de Fallos', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
