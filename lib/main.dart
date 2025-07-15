import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Temperature Monitor',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const BleTemperatureScreen(),
    );
  }
}

class BleTemperatureScreen extends StatefulWidget {
  const BleTemperatureScreen({super.key});

  @override
  State<BleTemperatureScreen> createState() => _BleTemperatureScreenState();
}

class _BleTemperatureScreenState extends State<BleTemperatureScreen> {
  final flutterReactiveBle = FlutterReactiveBle();

  final Uuid serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
  final Uuid characteristicUuid = Uuid.parse(
    "abcdefab-1234-5678-9abc-def123456789",
  );

  DiscoveredDevice? _device;
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notificationSub;

  String status = "Idle";
  double? temperature;
  int? timestamp;

  void _startScan() {
    setState(() {
      status = "Scanning...";
    });

    _scanSub = flutterReactiveBle
        .scanForDevices(withServices: [serviceUuid])
        .listen(
          (device) {
            if (device.name.isNotEmpty) {
              print("Found device: ${device.name} (${device.id})");
            }

            if (device.serviceUuids.contains(serviceUuid)) {
              _device = device;
              _scanSub?.cancel();
              _connectToDevice(device);
            }
          },
          onError: (e) {
            print("Scan error: $e");
            setState(() => status = "Scan failed");
          },
        );
  }

  void _connectToDevice(DiscoveredDevice device) {
    setState(() => status = "Connecting...");

    _connectionSub = flutterReactiveBle
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                print("Connected to device.");
                setState(() => status = "Connected");
                _subscribeToCharacteristic(device.id);
                break;
              case DeviceConnectionState.disconnected:
                print("Disconnected.");
                setState(() => status = "Disconnected");
                break;
              default:
                break;
            }
          },
          onError: (e) {
            print("Connection error: $e");
            setState(() => status = "Connection failed");
          },
        );
  }

  void _subscribeToCharacteristic(String deviceId) {
    print("Subscribing to characteristic...");
    _notificationSub = flutterReactiveBle
        .subscribeToCharacteristic(
          QualifiedCharacteristic(
            serviceId: serviceUuid,
            characteristicId: characteristicUuid,
            deviceId: deviceId,
          ),
        )
        .listen(
          (data) {
            _handleData(data);
          },
          onError: (e) {
            print("Notification error: $e");
            setState(() => status = "Error receiving data");
          },
        );
  }

  void _handleData(List<int> data) {
    if (data.length < 12) {
      print("Invalid data length: ${data.length}");
      return;
    }

    // Convert bytes to hex string
    final hexString = data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    print("Raw Hex: 0x$hexString");

    try {
      final timestampHex = hexString.substring(0, 8);
      final temperatureHex = hexString.substring(8, 12);

      final ts = int.parse(timestampHex, radix: 16);
      final temp = int.parse(temperatureHex, radix: 16) / 10;

      setState(() {
        timestamp = ts;
        temperature = temp;
      });

      print("Parsed Timestamp: $ts");
      print("Parsed Temperature: $temp °C");
    } catch (e) {
      print("Failed to parse data: $e");
    }
  }

  void _disconnect() {
    _connectionSub?.cancel();
    _notificationSub?.cancel();
    setState(() {
      status = "Disconnected";
      temperature = null;
      timestamp = null;
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  String _formatTimestamp(int? ts) {
    if (ts == null) return "N/A";
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ts * 1000,
      isUtc: true,
    ).toLocal();
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE Temperature Monitor")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("Status: $status", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            if (temperature != null)
              Text(
                "Temperature: ${temperature!.toStringAsFixed(1)} °C",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 10),
            if (timestamp != null)
              Text(
                "Timestamp: ${_formatTimestamp(timestamp)}",
                style: const TextStyle(fontSize: 18),
              ),
            const Spacer(),
            ElevatedButton(
              onPressed: _startScan,
              child: const Text("Scan & Connect"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _disconnect,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("Disconnect"),
            ),
          ],
        ),
      ),
    );
  }
}
