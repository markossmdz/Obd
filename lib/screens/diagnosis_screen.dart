import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'monitor_screen.dart';

class DiagnosisScreen extends StatefulWidget {
  const DiagnosisScreen({super.key});

  @override
  State<DiagnosisScreen> createState() => _DiagnosisScreenState();
}

class _DiagnosisScreenState extends State<DiagnosisScreen> {
  List<String> fallos = [];
  String revision = 'No';
  String log = '';
  bool cargando = false;
  bool errorConexion = false;

  @override
  void initState() {
    super.initState();
    leerDTCs();
  }

  Future<void> leerDTCs() async {
    setState(() {
      cargando = true;
      errorConexion = false;
      fallos.clear();
      revision = 'No';
      log = '';
    });

    final connection = MonitorScreen.connection;
    if (connection != null && connection.isConnected) {
      connection.input?.drain();
      connection.output.add(utf8.encode('03\r'));
      await connection.output.allSent;

      try {
        await for (Uint8List data in connection.input!.timeout(const Duration(seconds: 5))) {
          String response = ascii.decode(data);
          log += response;
          if (response.contains('43')) {
            List<String> dtcs = _parseDTCResponse(response);
            setState(() {
              fallos = dtcs;
              revision = dtcs.isNotEmpty ? 'Sí' : 'No';
              cargando = false;
            });
            break;
          }
          if (response.toUpperCase().contains('NO DATA') || response.toUpperCase().contains('NO DTC')) {
            setState(() {
              fallos = [];
              revision = 'No';
              cargando = false;
            });
            break;
          }
        }
      } on TimeoutException {
        setState(() {
          cargando = false;
          errorConexion = true;
          log += '\nTimeout esperando respuesta del OBD-II.';
        });
      } catch (e) {
        setState(() {
          cargando = false;
          errorConexion = true;
          log += '\nError inesperado: $e';
        });
      }
    } else {
      setState(() {
        log = 'No hay conexión con el OBD-II';
        cargando = false;
        errorConexion = true;
      });
    }
  }


  List<String> _parseDTCResponse(String response) {
    List<String> dtcs = [];
    response = response.replaceAll('\r', '').replaceAll('\n', '').replaceAll('>', '');
    int index = response.indexOf('43');
    if (index != -1) {
      String data = response.substring(index + 2).replaceAll(' ', '');
      for (int i = 0; i + 4 <= data.length; i += 4) {
        String dtcHex = data.substring(i, i + 4);
        String dtc = _dtcFromHex(dtcHex);
        if (dtc != 'P0000') dtcs.add(dtc);
      }
    }
    return dtcs;
  }

  String _dtcFromHex(String hex) {
    if (hex.length != 4) return '';
    int b1 = int.parse(hex.substring(0, 2), radix: 16);
    int b2 = int.parse(hex.substring(2, 4), radix: 16);

    List<String> types = ['P', 'C', 'B', 'U'];
    String type = types[(b1 & 0xC0) >> 6];
    int firstDigit = (b1 & 0x30) >> 4;
    int secondDigit = (b1 & 0x0F);
    String code = '$type$firstDigit${secondDigit.toRadixString(16).toUpperCase()}${b2.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    return code;
  }

  Widget _buildFalloCard(String dtc) {
    return Card(
      color: Colors.red.shade50,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
        title: Text(
          dtc,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.red),
        ),
        subtitle: const Text('Fallo detectado', style: TextStyle(color: Colors.black54)),
      ),
    );
  }

  Widget _buildNoFaultCard() {
    return Card(
      color: Colors.green.shade50,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.green, size: 32),
        title: const Text(
          'Sin fallos activos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.green),
        ),
        subtitle: const Text('El vehículo no presenta fallos en este momento.',
            style: TextStyle(color: Colors.black54)),
      ),
    );
  }

  Widget _buildRevisionCard() {
    return Card(
      color: revision == 'Sí' ? Colors.orange.shade50 : Colors.green.shade50,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
      child: ListTile(
        leading: Icon(
          revision == 'Sí' ? Icons.build_circle_rounded : Icons.verified,
          color: revision == 'Sí' ? Colors.orange : Colors.green,
          size: 32,
        ),
        title: Text(
          revision == 'Sí' ? '¡Revisión pendiente!' : 'Sin revisión pendiente',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: revision == 'Sí' ? Colors.orange : Colors.green,
          ),
        ),
        subtitle: Text(
          revision == 'Sí'
              ? 'Se recomienda revisar el vehículo por los fallos detectados.'
              : 'Todo está correcto.',
          style: const TextStyle(color: Colors.black54),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnosis de Fallos'),
        backgroundColor: Colors.red.shade400,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Text(
              'Estado del vehículo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red.shade400),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            cargando
                ? const Center(child: CircularProgressIndicator())
                : errorConexion
                ? Column(
              children: [
                Icon(Icons.bluetooth_disabled, color: Colors.red, size: 44),
                const SizedBox(height: 10),
                const Text(
                  'No hay conexión con el OBD-II',
                  style: TextStyle(fontSize: 18, color: Colors.red),
                ),
              ],
            )
                : fallos.isEmpty
                ? _buildNoFaultCard()
                : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...fallos.map(_buildFalloCard),
              ],
            ),
            const SizedBox(height: 12),
            _buildRevisionCard(),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: cargando ? null : leerDTCs,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar fallos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 17),
                padding: const EdgeInsets.symmetric(vertical: 14),
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