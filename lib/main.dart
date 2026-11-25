import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:my_http_project/login.dart';

/// Address of the bridge (bridge/bridge.py), for example
/// https://192.168.1.20:5000. The app never talks to the devices directly.
/// Set it when building: flutter run --dart-define=BRIDGE_URL=https://...
const String bridgeUrl = String.fromEnvironment('BRIDGE_URL');

/// The bridge's self-signed certificate (the PEM file), base64-encoded.
/// When set, the app trusts only this certificate for the bridge.
/// Set it when building: --dart-define=BRIDGE_CERT_B64=...
const String bridgeCertificateBase64 = String.fromEnvironment('BRIDGE_CERT_B64');

http.Client _createBridgeClient() {
  if (bridgeCertificateBase64.isEmpty) {
    // Falls back to the system's trusted certificate authorities
    return http.Client();
  }
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(base64Decode(bridgeCertificateBase64));
  return IOClient(HttpClient(context: context));
}

final http.Client bridgeClient = _createBridgeClient();

/// Sends a command to the bridge over HTTPS with the signed-in user's
/// Firebase ID token. Returns true if the device accepted it.
Future<bool> sendBridgeCommand(String path, Map<String, String> body) async {
  final uri = Uri.tryParse('$bridgeUrl/$path');
  if (uri == null || uri.scheme != 'https') {
    print('BRIDGE_URL must be an https:// address');
    return false;
  }
  final token = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (token == null) {
    return false;
  }
  try {
    final response = await bridgeClient
        .post(uri, headers: {'Authorization': 'Bearer $token'}, body: body)
        .timeout(const Duration(seconds: 10));
    return response.statusCode == 200;
  } catch (e) {
    print('Bridge request failed: ${e.runtimeType}');
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginPage(),
    );
  }
}

class ControlDevicePage extends StatefulWidget {
  const ControlDevicePage({super.key});

  @override
  _ControlDevicePageState createState() => _ControlDevicePageState();
}

class _ControlDevicePageState extends State<ControlDevicePage> {
  final Map<String, dynamic> deviceStates = {
    'lamp': false,
    'garage door': false,
    'door': false,
    'window': false,
    'thermostat': false,
    'air conditioning': false,
    'fan': 0, // 0: off, 1: low, 2: high
    'lawn sprinkler': false,
  };

  void _showDeviceError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not reach the device. Check that the bridge is running.'),
      ),
    );
  }

  Future<void> toggleDevice(String deviceId, bool state) async {
    final ok = await sendBridgeCommand('toggleDevice', {
      'deviceId': deviceId,
      'state': state ? '1' : '0',
    });
    if (!mounted) return;
    if (ok) {
      setState(() {
        deviceStates[deviceId] = state;
      });
    } else {
      _showDeviceError();
    }
  }

  Future<void> setThermostatTemperature(double temperature) async {
    final ok = await sendBridgeCommand('setTemperature', {
      'deviceId': 'thermostat',
      'temperature': temperature.toString(),
    });
    if (!ok) {
      _showDeviceError();
    }
  }

  Future<void> toggleFan(int state) async {
    final ok = await sendBridgeCommand('toggleDevice', {
      'deviceId': 'fan',
      'state': state.toString(),
    });
    if (!mounted) return;
    if (ok) {
      setState(() {
        deviceStates['fan'] = state;
      });
    } else {
      _showDeviceError();
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control IoT Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              DeviceButtonGroup(
                title: 'Lamp',
                state: deviceStates['lamp'],
                onToggle: (bool state) {
                  setState(() {
                    deviceStates['lamp'] = state; // Update the lamp state here
                    toggleDevice('lamp', state);
                  });
                },
              ),
              DeviceButtonGroup(
                title: 'Garage Door',
                state: deviceStates['garage door'],
                onOpen: () {
                  setState(() {
                    deviceStates['garage door'] =
                        true; // Update the garage door state here
                    toggleDevice('garage door', true);
                  });
                },
                onClose: () {
                  setState(() {
                    deviceStates['garage door'] =
                        false; // Update the garage door state here
                    toggleDevice('garage door', false);
                  });
                },
              ),
              DeviceButtonGroup(
                title: 'Door',
                state: deviceStates['door'] as bool,
                onOpen: () {
                  setState(() {
                    deviceStates['door'] =
                        true; // Update the garage door state here
                    toggleDevice('door', true);
                  });
                },
                onClose: () {
                  setState(() {
                    deviceStates['door'] =
                        false; // Update the garage door state here
                    toggleDevice('door', false);
                  });
                },
              ),
              DeviceButtonGroup(
                title: 'Window',
                state: deviceStates['window'] as bool,
                onOpen: () {
                  setState(() {
                    deviceStates['window'] =
                        true; // Update the garage door state here
                    toggleDevice('window', true);
                  });
                },
                onClose: () {
                  setState(() {
                    deviceStates['window'] =
                        false; // Update the garage door state here
                    toggleDevice('window', false);
                  });
                },
              ),
              DeviceButtonGroup(
                title: 'Thermostat',
                state: deviceStates['thermostat'] as bool,
                onSetTemperature: (double temperature) =>
                    setThermostatTemperature(temperature),
                hasTemperatureControl: true,
              ),
              DeviceButtonGroup(
                title: 'Air Conditioning Unit',
                state: deviceStates['air conditioning'] as bool,
                onToggle: (bool state) {
                  setState(
                    () {
                      deviceStates['air conditioning'] = state;
                      toggleDevice('air conditioning', state);
                    },
                  );
                },
              ),
              DeviceButtonGroup(
                title: 'Fan',
                state: deviceStates['fan'] != 0,
                onLow: () {
                  setState(() {
                    deviceStates['fan'] = 1; // Update the fan state here
                    toggleFan(1); // Low
                  });
                },
                onHigh: () {
                  setState(() {
                    deviceStates['fan'] = 2; // Update the fan state here
                    toggleFan(2); // High
                  });
                },
                onOff: () {
                  setState(() {
                    deviceStates['fan'] = 0; // Update the fan state here
                    toggleFan(0); // Off
                  });
                },
                fanState: deviceStates['fan'] as int, // Pass the fan state here
              ),
              DeviceButtonGroup(
                title: 'Lawn Sprinkler',
                state: deviceStates['lawn sprinkler'] as bool,
                onToggle: (bool state) {
                  setState(() {
                    deviceStates['lawn sprinkler'] =
                        state; // Update the lamp state here
                    toggleDevice('lawn sprinkler', state);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeviceButtonGroup extends StatelessWidget {
  final String title;
  final bool state;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;
  final Function(double)? onSetTemperature;
  final bool hasTemperatureControl;
  final Function(bool)? onToggle;
  final VoidCallback? onLow;
  final VoidCallback? onHigh;
  final VoidCallback? onOff;
  final int fanState;

  const DeviceButtonGroup({
    super.key,
    required this.title,
    required this.state,
    this.onOpen,
    this.onClose,
    this.onSetTemperature,
    this.hasTemperatureControl = false,
    this.onToggle,
    this.onLow,
    this.onHigh,
    this.onOff,
    this.fanState = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            if (onOpen != null)
              ElevatedButton(
                onPressed: onOpen,
                style: ElevatedButton.styleFrom(
                  backgroundColor: state ? Colors.green : Colors.grey,
                ),
                child: const Text('Open'),
              ),
            if (onClose != null)
              ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: !state ? Colors.red : Colors.grey,
                ),
                child: const Text('Close'),
              ),
            if (hasTemperatureControl)
              TemperatureInput(
                onSetTemperature: onSetTemperature!,
              ),
            if (onToggle != null)
              ElevatedButton(
                onPressed: () => onToggle!(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: !state ? Colors.red : Colors.grey,
                ),
                child: const Text('Turn Off'),
              ),
            if (onToggle != null)
              ElevatedButton(
                onPressed: () => onToggle!(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: state ? Colors.green : Colors.grey,
                ),
                child: const Text('Turn On'),
              ),
            if (onLow != null)
              ElevatedButton(
                onPressed: onLow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: fanState == 1 ? Colors.yellow : Colors.grey,
                ),
                child: const Text('Low'),
              ),
            if (onHigh != null)
              ElevatedButton(
                onPressed: onHigh,
                style: ElevatedButton.styleFrom(
                  backgroundColor: fanState == 2 ? Colors.orange : Colors.grey,
                ),
                child: const Text('High'),
              ),
            if (onOff != null)
              ElevatedButton(
                onPressed: onOff,
                style: ElevatedButton.styleFrom(
                  backgroundColor: fanState == 0 ? Colors.red : Colors.grey,
                ),
                child: const Text('Off'),
              ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class TemperatureInput extends StatefulWidget {
  final Function(double) onSetTemperature;

  const TemperatureInput({
    super.key,
    required this.onSetTemperature,
  });

  @override
  _TemperatureInputState createState() => _TemperatureInputState();
}

class _TemperatureInputState extends State<TemperatureInput> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Row(
        children: [
          const Text('Set Temperature:'),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter temperature',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a temperature';
                }
                double? temperature = double.tryParse(value);
                if (temperature == null) {
                  return 'Please enter a valid number';
                }
                if (temperature < -10 || temperature > 35) {
                  return 'Temperature must be between -10 and 35';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                double temperature = double.tryParse(_controller.text) ?? 20.0;
                widget.onSetTemperature(temperature);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}
