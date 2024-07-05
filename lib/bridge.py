from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

# Mapping of device IDs to their respective URLs
DEVICE_URLS = {
    'lamp': 'http://192.168.234.167:8765/toggleDevice',
    'garage door': 'http://192.168.234.167:8766/toggleDevice',
    'door': 'http://192.168.234.167:8767/toggleDevice',
    'window': 'http://192.168.234.167:8768/toggleDevice',
    'fan': 'http://192.168.234.167:8769/toggleDevice',
    'thermostat': 'http://192.168.234.167:8770/toggleDevice',
    'air conditioning': 'http://192.168.234.167:8771/toggleDevice',
    'lawn sprinkler': 'http://192.168.234.167:8772/toggleDevice',
}

@app.route('/toggleDevice', methods=['POST'])
def toggle_device():
    try:
        data = request.form
        device_id = data.get('deviceId')
        state = data.get('state')

        # Get the URL of the device based on the device_id
        iot_device_url = DEVICE_URLS.get(device_id)
        if not iot_device_url:
            return jsonify({'error': 'Invalid device ID'}), 400

        # Forward the request to the IoT device in Packet Tracer
        response = requests.post(iot_device_url, data={'deviceId': device_id, 'state': state})

        if response.status_code == 200:
            return jsonify({'message': response.text}), 200
        else:
            return jsonify({'error': response.text}), response.status_code
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
