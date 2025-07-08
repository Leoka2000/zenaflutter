import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:intl/intl.dart';

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

  void _startScanAndConnect() {
    setState(() {
      _status = "Scanning...";
    });

    flutterReactiveBle
        .scanForDevices(withServices: [serviceUuid])
        .listen(
          (device) async {
            setState(() {
              _status = "Connecting to ${device.name}...";
            });

            flutterReactiveBle.connectToDevice(id: device.id).listen((
              connectionState,
            ) {
              if (connectionState.connectionState ==
                  DeviceConnectionState.connected) {
                setState(() {
                  _status = "Connected!";
                  _connectedDevice = device;
                });

                _subscribeToCharacteristic(device.id);
              }
            });

            flutterReactiveBle.deinitialize(); // Stop scanning
          },
          onError: (error) {
            setState(() {
              _status = "Error scanning: $error";
            });
          },
        );
  }

  void _subscribeToCharacteristic(String deviceId) {
    setState(() {
      _status = "Subscribing to data...";
    });

    _dataStream = flutterReactiveBle.subscribeToCharacteristic(
      QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: deviceId,
      ),
    );

    _dataStream!.listen(
      (data) {
        if (data.isNotEmpty) {
          _handleHexData(data);
        }
      },
      onError: (error) {
        setState(() {
          _status = "Error receiving data: $error";
        });
      },
    );
  }

  void _handleHexData(List<int> data) {
    // Convert List<int> to hex string
    String hexString =
        "0x" + data.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    try {
      final cleanHex = hexString.substring(2);
      final timestampHex = cleanHex.substring(0, 8);
      final temperatureHex = cleanHex.substring(8, 12);

      final timestamp = int.parse(timestampHex, radix: 16);
      final temp = int.parse(temperatureHex, radix: 16) / 10;

      setState(() {
        _timestamp = timestamp;
        _temperature = temp;
        _status = "Receiving data...";
      });
    } catch (e) {
      setState(() {
        _status = "Failed to parse data";
      });
    }
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null) return "N/A";

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final format = DateFormat("yyyy-MM-dd HH:mm:ss");
    return format.format(date.toLocal());
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
