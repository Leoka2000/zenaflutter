import 'dart:async';
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
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

  final List<FlSpot> _temperaturePoints = [];
  final int _maxPoints = 100;
  double _xValue = 0;
  final double _step = 1;

  void _startScan() {
    setState(() {
      status = "Scanning...";
    });

    _scanSub = flutterReactiveBle
        .scanForDevices(withServices: [serviceUuid])
        .listen(
          (device) {
            if (device.serviceUuids.contains(serviceUuid)) {
              _device = device;
              _scanSub?.cancel();
              _connectToDevice(device);
            }
          },
          onError: (e) {
            setState(() => status = "Scan failed: $e");
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
            if (update.connectionState == DeviceConnectionState.connected) {
              setState(() => status = "Connected");
              _subscribeToCharacteristic(device.id);
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              setState(() => status = "Disconnected");
            }
          },
          onError: (e) {
            setState(() => status = "Connection failed: $e");
          },
        );
  }

  void _subscribeToCharacteristic(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    _notificationSub = flutterReactiveBle
        .subscribeToCharacteristic(characteristic)
        .listen(
          (data) => _handleData(data),
          onError: (e) {
            setState(() => status = "Error receiving data: $e");
          },
        );
  }

  void _handleData(List<int> data) {
    if (data.length < 12) return;

    final hexString = data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    try {
      final timestampHex = hexString.substring(0, 8);
      final temperatureHex = hexString.substring(8, 12);

      final ts = int.parse(timestampHex, radix: 16);
      final temp = int.parse(temperatureHex, radix: 16) / 10;

      setState(() {
        timestamp = ts;
        temperature = temp;

        if (_temperaturePoints.length >= _maxPoints) {
          _temperaturePoints.removeAt(0);
        }

        _temperaturePoints.add(FlSpot(_xValue, temp));
        _xValue += _step;
      });
    } catch (e) {
      print("Data parsing error: $e");
    }
  }

  void _disconnect() {
    _connectionSub?.cancel();
    _notificationSub?.cancel();
    setState(() {
      status = "Disconnected";
      temperature = null;
      timestamp = null;
      _temperaturePoints.clear();
      _xValue = 0;
    });
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
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _notificationSub?.cancel();
    super.dispose();
  }

  Widget _buildChart() {
    if (_temperaturePoints.isEmpty) {
      return const Center(child: Text("Waiting for data..."));
    }

    return AspectRatio(
      aspectRatio: 1.5,
      child: Padding(
        padding: const EdgeInsets.only(top: 20.0),
        child: LineChart(
          LineChartData(
            minX: _temperaturePoints.first.x,
            maxX: _temperaturePoints.last.x,
            minY: 0,
            maxY: 100,
            lineTouchData: const LineTouchData(enabled: false),
            gridData: FlGridData(
              show: true,
              horizontalInterval: 10,
              getDrawingHorizontalLine: (value) =>
                  FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1),
            ),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            clipData: const FlClipData.all(),
            lineBarsData: [
              LineChartBarData(
                spots: _temperaturePoints,
                isCurved: true,
                barWidth: 3,
                color: Colors.deepPurple,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
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
            const SizedBox(height: 10),
            if (temperature != null)
              Text(
                "Temperature: ${temperature!.toStringAsFixed(1)} °C",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (timestamp != null)
              Text(
                "Timestamp: ${_formatTimestamp(timestamp)}",
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 10),
            Expanded(child: _buildChart()),
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
