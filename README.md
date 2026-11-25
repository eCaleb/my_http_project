# Smart Home Controller

A Flutter app that controls a simulated smart home running in Cisco Packet Tracer.

Users sign in with Firebase Auth, then control devices from a single panel. The app sends every command over HTTPS to a small Python bridge, which checks who is asking and what they're asking for, then passes the command on to the matching device in the Packet Tracer simulation.

## Features

- **Email sign-up and login** with Firebase Auth, including email verification and password confirmation, plus a logout button.
- **Control eight simulated devices:**
  - lamp, air conditioning and lawn sprinkler: on and off
  - door, garage door and window: open and close
  - fan: off, low and high
  - thermostat: set a temperature, validated between -10 and 35°C
- Buttons change colour to show each device's current state, and the app tells you if a device can't be reached.
- **`bridge/bridge.py`:** a Flask service that checks each user's Firebase ID token, validates every command and forwards it to the simulated device. It has its own tests (`bridge/test_bridge.py`).

## Tech

Flutter, Dart, `http`, Firebase Auth, Python, Flask, Firebase Admin SDK / Google Auth, pytest, Cisco Packet Tracer.

## Security

The first version had no protection between the app and the devices. That's fixed as follows:

| Problem | Fix |
| --- | --- |
| Device commands went straight from the app to each device over plain HTTP, with no authentication, so anyone on the network could send them | The app only talks to the bridge, over HTTPS, and can be built to trust only the bridge's own certificate. Every request carries the user's Firebase ID token, and the bridge refuses anything without a valid token from a verified account. |
| The bridge forwarded any state value and passed raw error text back to the caller | The bridge only accepts known devices and valid values (on/off, fan speeds 0 to 2, temperatures -10 to 35), returns generic errors, limits request size and times out slow devices |
| The bridge's address and device addresses were hardcoded | The bridge address is set at build time, and device addresses live in `bridge/devices.json`, which isn't committed |
| Registration saved an unsalted SHA-256 hash of each password in Firestore, and login printed that record to the debug log | Removed. Firebase Auth already stores passwords securely, so the app keeps no copy or hash of them. |
| Error messages showed raw exception text, which could reveal whether an email had an account | One message for a wrong email or a wrong password |
| There was no way to log out, and an unverified account stayed signed in | Added a logout button, and unverified accounts are signed out straight away |

The link from the bridge to the devices is still plain HTTP, because it runs inside the Packet Tracer simulation. A real home would need TLS on that link too, or the bridge running on the same network segment as the devices with nothing else on it.

**One clean-up step in the Firebase console:** delete the old `users` collection in Firestore, because it still holds the unsalted password hashes from the earlier version.

## Running it

**1. Bridge certificate.** Create a self-signed certificate for the bridge machine's IP address (replace `192.168.1.20` with yours):

```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout bridge/key.pem -out bridge/cert.pem -subj "/CN=smart-home-bridge" \
  -addext "subjectAltName=IP:192.168.1.20"
```

Run all the commands here from the project folder.

**2. Bridge.** Build the devices in Packet Tracer, copy `bridge/devices.example.json` to `bridge/devices.json` and put in your devices' addresses. Then:

```bash
pip install -r bridge/requirements.txt
FIREBASE_PROJECT_ID=<your-project-id> BRIDGE_CERT=bridge/cert.pem BRIDGE_KEY=bridge/key.pem \
  python bridge/bridge.py
```

Optionally set `GOOGLE_APPLICATION_CREDENTIALS` to a Firebase service account key file (kept outside the repo) so the bridge also rejects revoked tokens.

**3. App.** Connect your own Firebase project with Email/Password sign-in, then run the app with the bridge's address and certificate:

```bash
flutter pub get
flutter run \
  --dart-define=BRIDGE_URL=https://192.168.1.20:5000 \
  --dart-define=BRIDGE_CERT_B64=$(base64 -w0 bridge/cert.pem)
```

On macOS, use `base64 -i bridge/cert.pem` instead. The app runs on Android and iOS.

**Tests:** `python -m pytest bridge`
