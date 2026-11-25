"""Tests for the bridge. Run with: python -m pytest bridge"""

import json

import pytest
import requests

from bridge import create_app, load_devices

DEVICES = {
    "lamp": "http://10.0.0.1:8765",
    "fan": "http://10.0.0.1:8769",
    "thermostat": "http://10.0.0.1:8770",
}

TOKENS = {
    "good": {"uid": "user-1", "email_verified": True},
    "unverified": {"uid": "user-2", "email_verified": False},
}


def fake_verify(token):
    if token not in TOKENS:
        raise ValueError("invalid token")
    return TOKENS[token]


class FakeResponse:
    def __init__(self, status_code):
        self.status_code = status_code


class FakeSession:
    def __init__(self, status_code=200, error=None):
        self.status_code = status_code
        self.error = error
        self.calls = []

    def post(self, url, data, timeout):
        self.calls.append((url, data, timeout))
        if self.error:
            raise self.error
        return FakeResponse(self.status_code)


def client_for(session):
    return create_app(DEVICES, fake_verify, session).test_client()


def auth(token="good"):
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.parametrize(
    "headers",
    [{}, {"Authorization": "good"}, {"Authorization": "Basic good"}, auth("forged"), auth("unverified")],
)
def test_rejects_missing_invalid_or_unverified_tokens(headers):
    session = FakeSession()
    response = client_for(session).post(
        "/toggleDevice", data={"deviceId": "lamp", "state": "1"}, headers=headers
    )
    assert response.status_code == 401
    assert session.calls == []


def test_forwards_a_valid_command_with_a_timeout():
    session = FakeSession()
    response = client_for(session).post(
        "/toggleDevice", data={"deviceId": "lamp", "state": "1"}, headers=auth()
    )
    assert response.status_code == 200
    assert session.calls == [
        ("http://10.0.0.1:8765/toggleDevice", {"deviceId": "lamp", "state": "1"}, 5)
    ]


@pytest.mark.parametrize(
    "form",
    [
        {"deviceId": "oven", "state": "1"},
        {"deviceId": "lamp", "state": "2"},
        {"deviceId": "lamp", "state": "on"},
        {"deviceId": "fan", "state": "3"},
        {"deviceId": "thermostat", "state": "1"},
        {"deviceId": "lamp"},
    ],
)
def test_rejects_invalid_commands(form):
    session = FakeSession()
    response = client_for(session).post("/toggleDevice", data=form, headers=auth())
    assert response.status_code == 400
    assert session.calls == []


def test_fan_accepts_high_speed():
    session = FakeSession()
    response = client_for(session).post(
        "/toggleDevice", data={"deviceId": "fan", "state": "2"}, headers=auth()
    )
    assert response.status_code == 200


@pytest.mark.parametrize("value", ["-10", "21.5", "35"])
def test_forwards_valid_temperatures(value):
    session = FakeSession()
    response = client_for(session).post(
        "/setTemperature", data={"temperature": value}, headers=auth()
    )
    assert response.status_code == 200
    assert session.calls[0][0] == "http://10.0.0.1:8770/setTemperature"


@pytest.mark.parametrize("value", ["-10.5", "36", "nan", "inf", "warm", ""])
def test_rejects_invalid_temperatures(value):
    session = FakeSession()
    response = client_for(session).post(
        "/setTemperature", data={"temperature": value}, headers=auth()
    )
    assert response.status_code == 400
    assert session.calls == []


def test_temperature_needs_a_token():
    session = FakeSession()
    response = client_for(session).post("/setTemperature", data={"temperature": "20"})
    assert response.status_code == 401
    assert session.calls == []


def test_device_errors_are_reported_without_details():
    response = client_for(FakeSession(status_code=500)).post(
        "/toggleDevice", data={"deviceId": "lamp", "state": "0"}, headers=auth()
    )
    assert response.status_code == 502
    assert response.get_json() == {"error": "Device error"}


def test_unreachable_devices_are_reported_without_details():
    session = FakeSession(error=requests.ConnectionError("10.0.0.1 refused the connection"))
    response = client_for(session).post(
        "/toggleDevice", data={"deviceId": "lamp", "state": "0"}, headers=auth()
    )
    assert response.status_code == 502
    assert "10.0.0.1" not in response.get_data(as_text=True)


def test_oversized_requests_are_refused():
    response = client_for(FakeSession()).post(
        "/toggleDevice", data={"deviceId": "lamp", "state": "1" * 5000}, headers=auth()
    )
    assert response.status_code == 413


def test_load_devices_strips_trailing_slashes(tmp_path):
    path = tmp_path / "devices.json"
    path.write_text(json.dumps({"lamp": "http://10.0.0.1:8765/"}))
    assert load_devices(path) == {"lamp": "http://10.0.0.1:8765"}


@pytest.mark.parametrize("content", ['["lamp"]', '{"lamp": 8765}', '{"lamp": "ftp://x"}'])
def test_load_devices_rejects_bad_files(tmp_path, content):
    path = tmp_path / "devices.json"
    path.write_text(content)
    with pytest.raises(ValueError):
        load_devices(path)
