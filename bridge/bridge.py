"""HTTPS bridge between the Smart Home Controller app and the devices in Cisco Packet Tracer.

The app never talks to the devices directly. Every request has to carry a
Firebase ID token for a signed-in user with a verified email, and each command
is checked before it is forwarded to the simulated device.

Environment variables:
  FIREBASE_PROJECT_ID             Firebase project the app signs in to (required)
  GOOGLE_APPLICATION_CREDENTIALS  optional service account key file; when set,
                                  revoked tokens are rejected as well
  BRIDGE_DEVICES                  device list (default: devices.json next to this file)
  BRIDGE_CERT, BRIDGE_KEY         TLS certificate and private key files
  BRIDGE_ALLOW_HTTP               set to 1 to serve plain HTTP, for local testing only
  BRIDGE_HOST, BRIDGE_PORT        default 0.0.0.0 and 5000
"""

import json
import logging
import math
import os
from pathlib import Path

import requests
from flask import Flask, jsonify, request

log = logging.getLogger("bridge")

ON_OFF = {"0", "1"}
FAN_SPEEDS = {"0", "1", "2"}
MIN_TEMPERATURE = -10.0
MAX_TEMPERATURE = 35.0
FORWARD_TIMEOUT_SECONDS = 5


def load_devices(path):
    """Read the device list: a JSON object mapping device names to base URLs."""
    with open(path, encoding="utf-8") as file:
        devices = json.load(file)
    if not isinstance(devices, dict) or not all(
        isinstance(name, str) and isinstance(url, str) and url.startswith("http")
        for name, url in devices.items()
    ):
        raise ValueError("The devices file must map device names to http(s) base URLs")
    return {name: url.rstrip("/") for name, url in devices.items()}


def firebase_verifier(project_id):
    """Return a function that checks a Firebase ID token and returns its claims.

    With a service account key (GOOGLE_APPLICATION_CREDENTIALS), the Firebase
    Admin SDK also rejects tokens that were revoked, for example after a
    password change. Without one, the token's signature, audience, issuer
    and expiry are still checked against Google's public keys.
    """
    if os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"):
        import firebase_admin
        from firebase_admin import auth

        firebase_admin.initialize_app(options={"projectId": project_id})
        return lambda token: auth.verify_id_token(token, check_revoked=True)

    from google.auth.transport import requests as google_requests
    from google.oauth2 import id_token

    transport = google_requests.Request()
    issuer = f"https://securetoken.google.com/{project_id}"

    def verify(token):
        claims = id_token.verify_firebase_token(token, transport, audience=project_id)
        if claims.get("iss") != issuer or not claims.get("sub"):
            raise ValueError("Token was not issued for this Firebase project")
        return claims

    return verify


def create_app(devices, verify_token, session=None):
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 1024  # commands are tiny
    http = session or requests.Session()

    def signed_in_user():
        scheme, _, token = request.headers.get("Authorization", "").partition(" ")
        if scheme != "Bearer" or not token:
            return None
        try:
            claims = verify_token(token)
        except Exception as error:  # invalid, expired or revoked token
            log.info("Rejected token: %s", type(error).__name__)
            return None
        if not claims.get("email_verified"):
            return None
        return claims

    def unauthorised():
        return jsonify(error="Unauthorised"), 401

    def forward(device_id, path, payload):
        try:
            response = http.post(
                f"{devices[device_id]}/{path}",
                data=payload,
                timeout=FORWARD_TIMEOUT_SECONDS,
            )
        except requests.RequestException as error:
            log.warning("Device %s unreachable: %s", device_id, type(error).__name__)
            return jsonify(error="Device unreachable"), 502
        if response.status_code != 200:
            log.warning("Device %s returned HTTP %s", device_id, response.status_code)
            return jsonify(error="Device error"), 502
        return jsonify(message="OK"), 200

    @app.post("/toggleDevice")
    def toggle_device():
        user = signed_in_user()
        if user is None:
            return unauthorised()
        device_id = request.form.get("deviceId", "")
        state = request.form.get("state", "")
        if device_id not in devices or device_id == "thermostat":
            return jsonify(error="Invalid device ID"), 400
        if state not in (FAN_SPEEDS if device_id == "fan" else ON_OFF):
            return jsonify(error="Invalid state"), 400
        log.info("User %s set %s to %s", user.get("uid"), device_id, state)
        return forward(device_id, "toggleDevice", {"deviceId": device_id, "state": state})

    @app.post("/setTemperature")
    def set_temperature():
        user = signed_in_user()
        if user is None:
            return unauthorised()
        if "thermostat" not in devices:
            return jsonify(error="No thermostat configured"), 400
        try:
            temperature = float(request.form.get("temperature", ""))
        except ValueError:
            return jsonify(error="Invalid temperature"), 400
        if not math.isfinite(temperature) or not MIN_TEMPERATURE <= temperature <= MAX_TEMPERATURE:
            return jsonify(error="Temperature must be between -10 and 35"), 400
        log.info("User %s set the thermostat to %s", user.get("uid"), temperature)
        return forward(
            "thermostat",
            "setTemperature",
            {"deviceId": "thermostat", "temperature": f"{temperature:g}"},
        )

    return app


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    project_id = os.environ.get("FIREBASE_PROJECT_ID")
    if not project_id:
        raise SystemExit("Set FIREBASE_PROJECT_ID to your Firebase project ID.")

    devices = load_devices(
        os.environ.get("BRIDGE_DEVICES") or Path(__file__).with_name("devices.json")
    )

    cert, key = os.environ.get("BRIDGE_CERT"), os.environ.get("BRIDGE_KEY")
    if cert and key:
        ssl_context = (cert, key)
    elif os.environ.get("BRIDGE_ALLOW_HTTP") == "1":
        ssl_context = None
        log.warning("Serving plain HTTP. Use this for local testing only.")
    else:
        raise SystemExit(
            "Set BRIDGE_CERT and BRIDGE_KEY to serve HTTPS "
            "(or BRIDGE_ALLOW_HTTP=1 for local testing only)."
        )

    app = create_app(devices, firebase_verifier(project_id))
    app.run(
        host=os.environ.get("BRIDGE_HOST", "0.0.0.0"),
        port=int(os.environ.get("BRIDGE_PORT", "5000")),
        ssl_context=ssl_context,
    )


if __name__ == "__main__":
    main()
