import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple BLE Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Simple BLE Scanner'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  late StreamSubscription<DiscoveredDevice> _scanSubscription;
  bool _isScanning = false;
  final List<DiscoveredDevice> _foundDevices = [];

  Future<void> _startScan() async {
    if (_isScanning) {
      _stopScan();
      return;
    }

    // Request location permission
    final status = await Permission.location.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permission is required to scan for BLE devices',
          ),
        ),
      );
      return;
    }

    setState(() {
      _foundDevices.clear();
      _isScanning = true;
    });

    _scanSubscription = _ble
        .scanForDevices(
          withServices: const [], // Scan all devices
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (device) {
            if (!_foundDevices.any((d) => d.id == device.id)) {
              setState(() {
                _foundDevices.add(device);
              });
            }
          },
          onError: (error) {
            setState(() {
              _isScanning = false;
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Scan error: $error')));
          },
        );

    // Stop scanning after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (_isScanning) {
        _stopScan();
      }
    });
  }

  void _stopScan() {
    _scanSubscription.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  @override
  void dispose() {
    if (_isScanning) {
      _scanSubscription.cancel();
    }
    super.dispose();
  }

  Widget _buildDeviceTile(DiscoveredDevice device) {
    final name = device.name.isNotEmpty ? device.name : 'Unknown Device';
    return ListTile(
      title: Text(name),
      subtitle: Text(device.id),
      trailing: Text(device.rssi.toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            label: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
            onPressed: _startScan,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _foundDevices.isEmpty
                ? Center(
                    child: Text(
                      _isScanning ? 'Scanning...' : 'No devices found',
                      style: const TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.separated(
                    itemCount: _foundDevices.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      return _buildDeviceTile(_foundDevices[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
