import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'monitor_screen.dart';

final db = FirebaseFirestore.instance;

final Map<String, List<String>> marcasModelos = {
  'Audi': [
    'A1', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8',
    'Q2', 'Q3', 'Q4 e-tron', 'Q5', 'Q6 e-tron', 'Q7', 'Q8',
    'TT', 'R8', 'e-tron GT', 'A6 e-tron'
  ],
  'BMW': [
    'Serie 1', 'Serie 2', 'Serie 3', 'Serie 4', 'Serie 5', 'Serie 6', 'Serie 7', 'Serie 8',
    'X1', 'X2', 'X3', 'X4', 'X5', 'X6', 'X7', 'XM',
    'Z4', 'i3', 'i4', 'i5', 'i7', 'i8', 'iX', 'iX1', 'iX3'
  ],
  'Ford': [
    'Fiesta', 'Focus', 'Fusion', 'Mondeo', 'Kuga', 'Puma', 'Edge', 'Escape', 'Explorer', 'EcoSport'
  ],
  'Honda': [
    'Civic', 'Accord', 'Jazz', 'Fit', 'HR-V', 'CR-V', 'ZR-V', 'Insight', 'e', 'S2000'
  ],
  'Hyundai': [
    'i10', 'i20', 'i30', 'i40', 'Elantra', 'Sonata', 'Veloster', 'Tucson', 'Santa Fe', 'Kona',
    'Bayon', 'Ioniq', 'Ioniq 5', 'Ioniq 6', 'Ioniq 9'
  ],
  'Kia': [
    'Picanto', 'Rio', 'Ceed', 'Stonic', 'Niro', 'Soul', 'Sportage', 'Sorento', 'EV6', 'EV9'
  ],
  'Mercedes': [
    'Clase A', 'Clase B', 'Clase C', 'Clase E', 'Clase S', 'CLA', 'CLS', 'GLA', 'GLB', 'GLC',
    'GLE', 'GLS', 'EQC', 'EQA', 'EQB', 'EQS', 'EQE', 'SLK', 'SL', 'AMG GT'
  ],
  'Opel': [
    'Adam', 'Karl', 'Corsa', 'Astra', 'Insignia', 'Mokka', 'Crossland', 'Grandland', 'Zafira', 'Meriva'
  ],
  'Peugeot': [
    '107', '108', '206', '207', '208', '301', '307', '308', '407', '508',
    '2008', '3008', '4008', '5008', 'RCZ', 'Rifter', 'Traveller'
  ],
  'Renault': [
    'Twingo', 'Clio', 'Megane', 'Fluence', 'Laguna', 'Talisman', 'Captur', 'Kadjar', 'Koleos', 'Arkana',
    'Austral', 'Scenic', 'Espace', 'ZOE', 'Twizy'
  ],
  'Seat': [
    'Mii', 'Ibiza', 'León', 'Toledo', 'Altea', 'Ateca', 'Arona', 'Tarraco'
  ],
  'Toyota': [
    'Aygo', 'Yaris', 'Corolla', 'Auris', 'Avensis', 'Camry', 'Prius', 'C-HR', 'RAV4', 'Highlander',
    'Land Cruiser', 'GR Yaris', 'GR86', 'GR Supra', 'bZ4X'
  ],
  'Volkswagen': [
    'Up!', 'Polo', 'Golf', 'Golf Plus', 'Jetta', 'Passat', 'Arteon', 'Tiguan', 'T-Roc', 'Touareg',
    'Touran', 'Sharan', 'ID.3', 'ID.4', 'ID.5', 'ID.7'
  ],
  'Volvo': [
    'S40', 'S60', 'S80', 'S90', 'V40', 'V50', 'V60', 'V70', 'V90',
    'XC40', 'XC60', 'XC70', 'XC90', 'C30', 'C70', 'C40', 'EX30', 'EX90', 'EM90'
  ]
};
final List<String> marcasVehiculos = marcasModelos.keys.toList();

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
  String? _marcaSeleccionada;
  String? _modeloSeleccionado;
  List<String> _modelosDisponibles = [];

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
    _getPairedDevices();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool hasVehicle = await _hasVehicleAssociated();
      if (!hasVehicle) {
        await _askForVehicleBrandAndModel(context);
      }
    });
  }

  Future<void> _checkBluetooth() async {
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

  Future<bool> _hasVehicleAssociated() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      DocumentSnapshot userDoc = await db.collection('garaje').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          return data['marca'] != null && data['modelo'] != null;
        }
      }
    } catch (e) {
      print('Error al verificar vehículo: $e');
    }
    return false;
  }

  Future<void> _askForVehicleBrandAndModel(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false, // No permitir cerrar sin seleccionar
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Datos de tu vehículo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Para personalizar la experiencia, necesitamos conocer tu vehículo:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  DropdownButton<String>(
                    value: _marcaSeleccionada,
                    hint: const Text('Elige una marca'),
                    isExpanded: true,
                    onChanged: (String? newValue) {
                      setState(() {
                        _marcaSeleccionada = newValue;
                        _modelosDisponibles = marcasModelos[newValue] ?? [];
                        _modeloSeleccionado = null;
                      });
                    },
                    items: marcasVehiculos.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: _modeloSeleccionado,
                    hint: const Text('Elige un modelo'),
                    isExpanded: true,
                    onChanged: _marcaSeleccionada == null ? null : (String? newValue) {
                      setState(() {
                        _modeloSeleccionado = newValue;
                      });
                    },
                    items: _modelosDisponibles.map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: (_marcaSeleccionada != null && _modeloSeleccionado != null)
                      ? () async {
                    User? user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      try {
                        await db.collection('garaje').doc(user.uid).set({
                          'usuario': user.uid,
                          'mail': user.email ?? '',
                          'marca': _marcaSeleccionada,
                          'modelo': _modeloSeleccionado,
                        }, SetOptions(merge: true));

                        Navigator.of(context).pop();

                        // Mostrar confirmación
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Vehículo $_marcaSeleccionada $_modeloSeleccionado guardado correctamente'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error al guardar: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                      : null,
                  child: Text(
                    'Guardar',
                    style: TextStyle(
                      color: (_marcaSeleccionada != null && _modeloSeleccionado != null)
                          ? Colors.blue
                          : Colors.grey,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
    int retries = 0;
    while (retries < 3) {
      try {
        connection = await BluetoothConnection.toAddress(obdDevice!.address)
            .timeout(const Duration(seconds: 8));
        setState(() {
          status = 'Conectado a ${obdDevice!.name}';
          isConnecting = false;
          hasError = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MonitorScreen(connection: connection!),
          ),
        );
        return;
      } catch (e) {
        retries++;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    setState(() {
      status =
      'No se pudo conectar tras varios intentos. Asegúrate de que el OBD-II está encendido, emparejado y sin otros usuarios conectados.';
      isConnecting = false;
      hasError = true;
    });
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
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF001823),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(12.0),
          ),
        ),
        title: const Text('Conexión con el OBD-II'),
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
              size: 96,
            ),
            const SizedBox(height: 24),
            Text(
              status,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: hasError ? Colors.red : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 26,
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
                    color: azul.withOpacity(0.5),
                    blurRadius: 16,
                    offset: const Offset(8, 8),
                  ),
                ],
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: azul,
                  textStyle: const TextStyle(fontSize: 20),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
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
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MonitorScreen(connection: null),
                  ),
                );
              },
              child: const Text('Saltar'),
            ),
          ],
        ),
      ),
    );
  }
}
