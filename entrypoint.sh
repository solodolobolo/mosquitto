#!/bin/ash
set -e

# Only create the password file if it DOES NOT exist
if [ -n "$MQTT_USER" ] && [ -n "$MQTT_PASSWORD" ] && [ ! -f "/mosquitto/config/mosquitto.passwd" ]; then
    echo "Creating new password file..."
    mosquitto_passwd -b -c /mosquitto/config/mosquitto.passwd "$MQTT_USER" "$MQTT_PASSWORD"
    chown mosquitto:mosquitto /mosquitto/config/mosquitto.passwd
    chmod 600 /mosquitto/config/mosquitto.passwd
fi

exec "$@"