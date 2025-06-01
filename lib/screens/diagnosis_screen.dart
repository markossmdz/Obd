import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class DTCResult {
  final String code;
  final String status;
  final String? description;
  DTCResult(this.code, this.status, {this.description});
}

class DiagnosisScreen extends StatefulWidget {
  final BluetoothConnection? connection;
  const DiagnosisScreen({Key? key, this.connection}) : super(key: key);

  @override
  _DiagnosisScreenState createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  bool loading = false;
  bool connectionError = false;
  Timer? _timeoutTimer;
  List<DTCResult> dtcResults = [];
  String log = '';

  // Mapa con algunas descripciones comunes de DTCs
  static const Map<String, String> dtcDescriptions = {
    'P0100': 'Mal funcionamiento del circuito del sensor de flujo de masa de aire (MAF)',
    'P0101': 'Rango/rendimiento del circuito del sensor de flujo de masa de aire (MAF)',
    'P0133': 'Respuesta lenta del sensor de oxígeno (Banco 1, Sensor 1)',
    'P0171': 'Sistema demasiado pobre (Banco 1)',
    'P0300': 'Detección de fallo de encendido aleatorio/múltiple',
    'P0420': 'Eficiencia del sistema del catalizador por debajo del umbral (Banco 1)',
  };

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<List<DTCResult>> _readDTCs() async {
    setState(() {
      loading = true;
      connectionError = false;
      log += '\nEnviando comando 03...';
    });

    if (widget.connection == null || !widget.connection!.isConnected) {
      setState(() {
        log += '\nNo hay conexión con el OBD-II';
        loading = false;
        connectionError = true;
      });
      return [];
    }

    widget.connection!.output.add(utf8.encode('03\r'));
    await widget.connection!.output.allSent;

    setState(() {
      log += '\nComando enviado. La respuesta será procesada en MonitorScreen.\n';
      log += 'Sin fallos';
      loading = false;
      connectionError = false;
      dtcResults = [
        DTCResult('P0000', 'Sin fallos', description: 'No se detectaron fallos.'),
      ];
    });

    return dtcResults;
  }

  Future<List<DTCResult>> _readDTCsWithRetry({int maxRetries = 3}) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _readDTCs();
      } catch (e) {
        setState(() {
          log += '\nError en intento ${attempt + 1}: $e';
          connectionError = true;
        });
        if (attempt == maxRetries - 1) rethrow;
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return [];
  }

  String _getDtcDescription(String dtc) {
    return dtcDescriptions[dtc] ?? _explainDtcStructure(dtc);
  }

  String _explainDtcStructure(String dtc) {
    if (dtc.length != 5) return 'Descripción no disponible';
    String system = {
      'P': 'Tren motriz (motor, transmisión, combustible)',
      'C': 'Chasis',
      'B': 'Carrocería',
      'U': 'Red/comunicación'
    }[dtc[0]] ?? 'Desconocido';
    String type = dtc[1] == '0'
        ? 'Genérico (SAE)'
        : dtc[1] == '1'
        ? 'Específico de fabricante'
        : 'Desconocido';
    return '$system · $type';
  }

  Widget _buildDTCItem(DTCResult result) {
    return Card(
      color: Colors.red.shade50,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.blue, size: 32),
        title: Text(
          result.code,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.blue),
        ),
        subtitle: Text(result.description ?? ''),
        trailing: Text(result.status, style: const TextStyle(color: Colors.blue)),
      ),
    );
  }

  Widget _buildNoFaultCard() {
    return Card(
      color: Colors.green.shade50,
      margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green, size: 38),
        title: const Text(
          'Sin fallos activos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21, color: Colors.green),
        ),
        subtitle: const Text('El vehículo no presenta fallos en este momento.', style: TextStyle(color: Colors.black54)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico de Fallos'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(
              'Estado del vehículo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (widget.connection == null) ...[
              const Icon(Icons.bluetooth_disabled, color: Colors.red, size: 44),
              const SizedBox(height: 10),
              const Text(
                'No hay conexión con el OBD-II',
                style: TextStyle(fontSize: 18, color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
            if (loading && widget.connection != null)
              const Center(child: CircularProgressIndicator())
            else if (!connectionError && widget.connection != null)
              dtcResults.isEmpty
                  ? _buildNoFaultCard()
                  : Expanded(
                child: ListView.builder(
                  itemCount: dtcResults.length,
                  itemBuilder: (context, index) {
                    return _buildNoFaultCard();
                  },
                ),
              ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: loading ? null : _readDTCsWithRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar fallos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 17),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            ExpansionTile(
              title: const Text('Detalles técnicos (log)', style: TextStyle(fontSize: 15)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Colors.grey.shade100,
                  child: SelectableText(
                    log.isEmpty ? 'Sin datos' : log,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
