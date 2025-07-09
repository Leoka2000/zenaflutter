import 'dart:async';
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

  final String _targetDeviceName = "MySensor";

  DiscoveredDevice? _connectedDevice;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _dataSubscription;

  String _status = "Disconnected";
  double? _temperature;
  int? _timestamp;
  int _scanCount = 0;

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

  Future<void> _startScanAndConnect() async {
    final ready = await _checkPermissionsAndLocation();
    if (!ready) {
      setState(() => _status = "Permissions or location service missing");
      return;
    }

    setState(() {
      _status = "Scanning...";
      _scanCount = 0;
      _connectedDevice = null;
    });

    final foundDevices = <String, DiscoveredDevice>{};

    _scanSubscription = flutterReactiveBle
        .scanForDevices(withServices: []) // empty list means scan all
        .listen(
          (device) {
            if (!foundDevices.containsKey(device.id)) {
              foundDevices[device.id] = device;
              _scanCount++;
              print("🔍 Found device: ${device.name} (${device.id})");

              if (device.name == _targetDeviceName) {
                _scanSubscription?.cancel();
                _connectToDevice(device);
              }
            }
          },
          onError: (e) {
            setState(() => _status = "Scan failed: $e");
            print("❌ Scan error: $e");
          },
        );

    await Future.delayed(Duration(seconds: 10));
    if (_connectedDevice == null) {
      await _scanSubscription?.cancel();

      if (foundDevices.isNotEmpty) {
        final fallbackDevice = foundDevices.values.first;
        print(
          "⚠️ Target not found, connecting to first found device: ${fallbackDevice.name}",
        );
        _connectToDevice(fallbackDevice);
      } else {
        setState(() => _status = "No BLE devices found");
      }
    }
  }

  void _connectToDevice(DiscoveredDevice device) {
    setState(() => _status = "Connecting to ${device.name}...");
    _connectionSubscription = flutterReactiveBle
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: {
            serviceUuid: [characteristicUuid],
          },
        )
        .listen(
          (connectionState) {
            print("🔌 Connection state: ${connectionState.connectionState}");

            if (connectionState.connectionState ==
                DeviceConnectionState.connected) {
              setState(() {
                _connectedDevice = device;
                _status = "Connected to ${device.name}";
              });
              _subscribeToCharacteristic(device.id);
            } else if (connectionState.connectionState ==
                DeviceConnectionState.disconnected) {
              setState(() {
                _status = "Disconnected";
                _connectedDevice = null;
              });
            }
          },
          onError: (e) {
            print("❌ Connection error: $e");
            setState(() => _status = "Connection failed: $e");
          },
        );
  }

  void _subscribeToCharacteristic(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    setState(() => _status = "Subscribing to characteristic...");

    _dataSubscription = flutterReactiveBle
        .subscribeToCharacteristic(characteristic)
        .listen(
          (data) {
            print("📦 Data received: $data");

            if (data.length >= 6) {
              _parseData(data);
            } else {
              setState(() => _status = "Invalid data length");
            }
          },
          onError: (e) {
            print("❌ Data subscription error: $e");
            setState(() => _status = "Failed to subscribe to data");
          },
        );
  }

  void _parseData(List<int> data) {
    try {
      final byteData = ByteData.sublistView(Uint8List.fromList(data));
      final timestamp = byteData.getUint32(0, Endian.big);
      final tempRaw = byteData.getInt16(4, Endian.big);
      final temperature = tempRaw / 10.0;

      setState(() {
        _timestamp = timestamp;
        _temperature = temperature;
        _status = "Data received";
      });

      print("🕒 Timestamp: ${_formatTimestamp(timestamp)}");
      print("🌡️ Temperature: $temperature °C");
    } catch (e) {
      print("❌ Parse error: $e");
      setState(() => _status = "Failed to parse data");
    }
  }

  String _formatTimestamp(int? ts) {
    if (ts == null) return "N/A";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return DateFormat("yyyy-MM-dd HH:mm:ss").format(dt.toLocal());
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Dashboard"),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Status: $_status", style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Text("Scan attempts: $_scanCount"),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startScanAndConnect,
              child: Text("Connect to BLE Device"),
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
