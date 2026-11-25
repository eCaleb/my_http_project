# Smart Home Controller

A Flutter app that controls a simulated smart home running in Cisco Packet Tracer.

Users sign in with Firebase Auth, then control devices from a single panel. Each command is sent as an HTTP request to the matching device in the Packet Tracer simulation.

## Features

- **Email sign-up and login** with Firebase Auth, including email verification and password confirmation.
- **Control eight simulated devices:**
  - lamp, air conditioning and lawn sprinkler: on and off
  - door, garage door and window: open and close
  - fan: off, low and high
  - thermostat: set a temperature, validated between -10 and 35°C
- Buttons change colour to show each device's current state.
- **`lib/bridge.py`:** a small Flask service that forwards device commands to the simulation and rejects any device ID that isn't on its list.

## Tech

Flutter, Dart, `http`, Firebase Auth, Cloud Firestore, Python, Flask, Cisco Packet Tracer.

## Security notes

This was a lab simulation, not something built for a real home:

- Device commands travel over plain HTTP with no authentication, so anyone on the same network could send them. A real system would need TLS and an authenticated channel between the app and each device.
- As well as using Firebase Auth, the app saves an unsalted SHA-256 hash of each password in Firestore and checks it at login. That adds no protection and is weaker than Firebase's own password hashing, so I'd remove it.
- Device addresses are hardcoded in the app. They belong in configuration.

## Running it

1. Build the devices in Cisco Packet Tracer and note their IP address and ports.
2. Update the device URLs in `lib/main.dart`, and in `lib/bridge.py` if you use the bridge.
3. Connect your own Firebase project with Email/Password sign-in and Cloud Firestore.
4. Run `flutter pub get`, then `flutter run`. For the bridge: `pip install flask requests`, then `python lib/bridge.py`.
