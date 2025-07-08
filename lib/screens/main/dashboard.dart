import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart';

class DashboardPage extends StatefulWidget {
  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final flutterReactiveBle = FlutterReactiveBle();

  final Uuid serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
  final Uuid characteristicUuid = Uuid.parse(
    "abcdefab-1234-5678-9abc-def123456789",
  );

  DiscoveredDevice? _connectedDevice;
  Stream<List<int>>? _dataStream;

  String _status = "Disconnected";
  double? _temperature;
  int? _timestamp;

  Future<bool> _checkPermissionsAndLocation() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ];

    final statuses = await permissions.request();
    final permissionsGranted = statuses.values.every(
      (status) => status.isGranted,
    );

    final location = Location();
    bool locationEnabled = await location.serviceEnabled();
    if (!locationEnabled) {
      locationEnabled = await location.requestService();
    }

    return permissionsGranted && locationEnabled;
  }

  void _startScanAndConnect() async {
    final ready = await _checkPermissionsAndLocation();

    if (!ready) {
      setState(() => _status = "Permissions or Location not available");
      return;
    }

    setState(() => _status = "Scanning...");

    flutterReactiveBle
        .scanForDevices(withServices: [])
        .listen(
          (device) {
            if (_connectedDevice == null && device.name.isNotEmpty) {
              print("Found device: ${device.name} (${device.id})");

              setState(() {
                _connectedDevice = device;
                _status = "Connecting to ${device.name}...";
              });

              flutterReactiveBle
                  .connectToDevice(id: device.id)
                  .listen(
                    (connectionState) {
                      if (connectionState.connectionState ==
                          DeviceConnectionState.connected) {
                        setState(() => _status = "Connected to ${device.name}");
                        _subscribeToCharacteristic(device.id);
                      }
                    },
                    onError: (e) {
                      setState(() => _status = "Connection failed: $e");
                    },
                  );
            }
          },
          onError: (e) {
            setState(() => _status = "Scan error: $e");
          },
        );
  }

  void _subscribeToCharacteristic(String deviceId) {
    setState(() => _status = "Subscribing to data...");

    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    _dataStream = flutterReactiveBle.subscribeToCharacteristic(characteristic);

    _dataStream!.listen(
      (data) {
        if (data.length >= 6) {
          _parseData(data);
        } else {
          setState(() => _status = "Invalid data received");
        }
      },
      onError: (e) {
        setState(() => _status = "Error receiving data: $e");
      },
    );
  }

  void _parseData(List<int> data) {
    try {
      final byteData = ByteData.sublistView(Uint8List.fromList(data));

      final timestamp = byteData.getUint32(0, Endian.big);
      final temperatureRaw = byteData.getInt16(4, Endian.big);
      final temperature = temperatureRaw / 10;

      setState(() {
        _timestamp = timestamp;
        _temperature = temperature;
        _status = "Data received";
      });
    } catch (e) {
      setState(() => _status = "Data parse error: $e");
    }
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return "N/A";
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat("yyyy-MM-dd HH:mm:ss").format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Status: $_status', style: TextStyle(fontSize: 16)),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startScanAndConnect,
              child: Text('Connect to BLE Device'),
            ),
            SizedBox(height: 32),
            if (_temperature != null)
              Text(
                "Temperature: ${_temperature!.toStringAsFixed(1)} °C",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            if (_timestamp != null)
              Text(
                "Timestamp: ${_formatTimestamp(_timestamp)}",
                style: TextStyle(fontSize: 16),
              ),
          ],
        ),
      ),
    );
  }
}
