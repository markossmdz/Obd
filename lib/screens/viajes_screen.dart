import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:url_launcher/url_launcher.dart';

class TripRecordingScreen extends StatefulWidget {
  final BluetoothConnection? connection;

  const TripRecordingScreen({Key? key, required this.connection}) : super(key: key);

  @override
  State<TripRecordingScreen> createState() => _TripRecordingScreenState();
}

class _TripRecordingScreenState extends State<TripRecordingScreen> {
  double? odoInicial;
  double? consumoInicial;
  double kmRecorridos = 0;
  double consumoViaje = 0;
  double velocidadMedia = 0;
  double consumoMedio = 0;
  double consumoInstantaneo = 0;
  Duration tiempoTranscurrido = Duration.zero;

  Timer? timer;
  DateTime? tiempoInicio;
  bool viajeActivo = false;
  bool viajePausado = false;
  String? error;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<String> _sendOBDCommand(String command) async {
    if (widget.connection == null || !widget.connection!.isConnected) {
      throw Exception('No hay conexión Bluetooth');
    }

    final completer = Completer<String>();
    late StreamSubscription subscription;
    final buffer = StringBuffer();

    subscription = widget.connection!.input!.listen((data) {
      final response = String.fromCharCodes(data);
      buffer.write(response);
      if (response.contains('>')) {
        completer.complete(buffer.toString());
        subscription.cancel();
      }
    });

    widget.connection!.output.add(Utf8Encoder().convert('$command\r'));
    await widget.connection!.output.allSent;

    // Timeout para evitar bloqueo indefinido
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      subscription.cancel();
      throw TimeoutException('Timeout esperando respuesta OBD');
    });
  }

  Future<double?> _leerOdometro() async {
    try {
      final response = await _sendOBDCommand('01A6');
      if (response.contains('NO DATA')) return null;
      // Ejemplo de parseo sencillo (depende del formato real)
      final clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (clean.length < 6) return null;
      final value = int.parse(clean.substring(2, 6), radix: 16);
      // Según protocolo, valor en km o millas, ajusta según tu caso
      return value.toDouble();
    } catch (e) {
      debugPrint('Error leer odómetro: $e');
      return null;
    }
  }

  Future<double?> _leerConsumoTotal() async {
    try {
      final response = await _sendOBDCommand('015E'); // PID consumo total (ejemplo)
      if (response.contains('NO DATA')) return null;
      final clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (clean.length < 6) return null;
      final value = int.parse(clean.substring(2, 6), radix: 16);
      // Ajusta la conversión según protocolo y unidad (litros, ml, etc.)
      return value.toDouble() / 10; // Ejemplo: decilitros a litros
    } catch (e) {
      debugPrint('Error leer consumo total: $e');
      return null;
    }
  }

  Future<double?> _leerVelocidad() async {
    try {
      final response = await _sendOBDCommand('010D');
      if (response.contains('NO DATA')) return null;
      final clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (clean.length < 4) return null;
      final value = int.parse(clean.substring(2, 4), radix: 16);
      return value.toDouble();
    } catch (e) {
      debugPrint('Error leer velocidad: $e');
      return null;
    }
  }

  Future<double?> _leerConsumoInstantaneo() async {
    try {
      final response = await _sendOBDCommand('015E'); // PID consumo instantáneo (ejemplo)
      if (response.contains('NO DATA')) return null;
      final clean = response.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      if (clean.length < 6) return null;
      final value = int.parse(clean.substring(2, 6), radix: 16);
      return value.toDouble() / 10;
    } catch (e) {
      debugPrint('Error leer consumo instantáneo: $e');
      return null;
    }
  }

  void _startTrip() async {
    if (viajeActivo) return;

    setState(() {
      error = null;
    });

    final odo = await _leerOdometro();
    final consumo = await _leerConsumoTotal();

    if (odo == null || consumo == null) {
      setState(() {
        error = 'No se pudo leer odómetro o consumo total. Tu coche puede no soportar estos datos.';
      });
      return;
    }

    odoInicial = odo;
    consumoInicial = consumo;
    tiempoInicio = DateTime.now();

    setState(() {
      kmRecorridos = 0;
      consumoViaje = 0;
      velocidadMedia = 0;
      consumoMedio = 0;
      viajeActivo = true;
      viajePausado = false;
      tiempoTranscurrido = Duration.zero;
    });

    timer = Timer.periodic(const Duration(seconds: 2), (_) => _actualizarDatos());
  }

  void _actualizarDatos() async {
    if (!viajeActivo || viajePausado) return;

    final odoActual = await _leerOdometro();
    final consumoActual = await _leerConsumoTotal();
    final velocidadActual = await _leerVelocidad();
    final consumoInst = await _leerConsumoInstantaneo();

    if (odoActual == null || consumoActual == null) {
      setState(() {
        error = 'Error al leer datos durante el viaje.';
      });
      return;
    }

    final ahora = DateTime.now();
    final duracion = ahora.difference(tiempoInicio!);

    setState(() {
      tiempoTranscurrido = duracion;
      kmRecorridos = odoActual - (odoInicial ?? 0);
      consumoViaje = consumoActual - (consumoInicial ?? 0);
      velocidadMedia = duracion.inSeconds > 0 ? (kmRecorridos / (duracion.inSeconds / 3600)) : 0;
      consumoMedio = kmRecorridos > 0 ? (consumoViaje / kmRecorridos) * 100 : 0;
      consumoInstantaneo = consumoInst ?? 0;
    });
  }

  void _pauseResumeTrip() {
    if (!viajeActivo) return;
    setState(() {
      viajePausado = !viajePausado;
    });
  }

  void _finishTrip() {
    if (!viajeActivo) return;

    timer?.cancel();

    // Aquí guardarías los datos en la BBDD
    debugPrint('Viaje finalizado:');
    debugPrint('Km recorridos: $kmRecorridos');
    debugPrint('Consumo total: $consumoViaje');
    debugPrint('Velocidad media: $velocidadMedia');
    debugPrint('Consumo medio: $consumoMedio');
    debugPrint('Duración: $tiempoTranscurrido');

    setState(() {
      viajeActivo = false;
      viajePausado = false;
      odoInicial = null;
      consumoInicial = null;
      kmRecorridos = 0;
      consumoViaje = 0;
      velocidadMedia = 0;
      consumoMedio = 0;
      consumoInstantaneo = 0;
      tiempoTranscurrido = Duration.zero;
      error = null;
    });
  }

  Future<void> _openWaze() async {
    const wazeUrl = 'waze://';
    if (await canLaunch(wazeUrl)) {
      await launch(wazeUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Waze no está instalado')),
      );
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF1976D2);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Viaje'),
        backgroundColor: azul,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            Card(
              child: ListTile(
                title: const Text('Tiempo transcurrido'),
                trailing: Text(_formatDuration(tiempoTranscurrido), style: const TextStyle(fontSize: 18)),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Kilómetros recorridos'),
                trailing: Text(kmRecorridos.toStringAsFixed(2), style: const TextStyle(fontSize: 18)),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Consumo total (L)'),
                trailing: Text(consumoViaje.toStringAsFixed(2), style: const TextStyle(fontSize: 18)),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Velocidad media (km/h)'),
                trailing: Text(velocidadMedia.toStringAsFixed(2), style: const TextStyle(fontSize: 18)),
              ),
            ),
            Card(
              child: ListTile(
                title: const Text('Consumo medio (L/100km)'),
                trailing: Text(consumoMedio.toStringAsFixed(2), style: const TextStyle(fontSize: 18)),
              ),
            ),
            Card(
              color: Colors.grey.shade200,
              child: ListTile(
                title: const Text('Consumo instantáneo (L/100km)'),
                trailing: Text(consumoInstantaneo.toStringAsFixed(2), style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: viajeActivo ? null : _startTrip,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
                ElevatedButton.icon(
                  onPressed: viajeActivo ? _pauseResumeTrip : null,
                  icon: Icon(viajePausado ? Icons.play_arrow : Icons.pause),
                  label: Text(viajePausado ? 'Reanudar' : 'Pausar'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                ElevatedButton.icon(
                  onPressed: viajeActivo ? _finishTrip : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Finalizar'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
