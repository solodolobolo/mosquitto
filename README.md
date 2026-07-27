# Custom Eclipse Mosquitto Docker Image

Containers built with this Dockerfile compile Mosquitto from source using published tarballs. It is specifically tailored to include **WebSockets** support via `libwebsockets` (v5.0.0) and features a unified volume structure with automated credential generation.

## Features

* **WebSockets Enabled:** Includes a pre-configured listener on port `9001` alongside the standard MQTT listener on port `1883`.
* **Automated Passwords:** Set `MQTT_USER` and `MQTT_PASSWORD` environment variables to automatically generate a secure `mosquitto.passwd` file on first boot.
* **Unified Mount Point:** Configuration, data, and logs are all consolidated under a single `/mosquitto` directory.
* **Lean & Secure:** Built via a multi-stage Alpine Dockerfile, running as a non-root `mosquitto` user (UID/GID 1883).

## Quick Start

To spin up the broker with authentication enabled and both ports exposed, run:

```bash
docker run -d --name mosquitto \
  -p 1883:1883 \
  -p 9001:9001 \
  -e MQTT_USER=my_user \
  -e MQTT_PASSWORD=my_secure_password \
  -v mosquitto_data:/mosquitto \
  solodolobolo/mosquitto:latest

```

This will automatically create your credentials, pipe the broker logs directly to the Docker daemon (`docker logs mosquitto`), and save your persistent data in a Docker named volume.

## Volumes & Directory Structure

You only need to mount a single Docker volume:

* `/mosquitto`

Inside this volume, Mosquitto uses the following subdirectories:

* `/mosquitto/config` (Holds your `mosquitto.conf` and `mosquitto.passwd`)
* `/mosquitto/data` (Holds your persistent database if `persistence true` is set)
* `/mosquitto/log` (Available if you choose to route logs to a file instead of `stdout`)

## Customizing the Configuration

A production-ready `mosquitto.conf` is baked directly into the Docker image. By default, it requires authentication, enables WebSockets, and outputs logs to stdout.

If you are using a **Docker named volume** (like the Quick Start above), the container will automatically copy the default configuration into your volume the first time it spins up. You can then edit it by executing into the container.

### Using Local Bind Mounts

If you prefer to mount a local folder from your host machine, **do not mount an empty folder**, or Docker will hide the default configuration file and Mosquitto will crash. Instead, extract the default file first:

```bash
# 1. Extract the default config from the image to your current local directory
docker run --rm solodolobolo/mosquitto:latest cat /mosquitto/config/mosquitto.conf > ./mosquitto.conf

# 2. Edit your local ./mosquitto.conf file however you like

# 3. Run the container and mount your local file directly over the default one
docker run -d --name mosquitto \
  -p 1883:1883 \
  -p 9001:9001 \
  -e MQTT_USER=my_user \
  -e MQTT_PASSWORD=my_secure_password \
  -v $(pwd)/mosquitto.conf:/mosquitto/config/mosquitto.conf \
  -v mosquitto_data:/mosquitto/data \
  solodolobolo/mosquitto:latest

```

## Build Instructions

Versions for Mosquitto, libwebsockets, and cJSON are securely pinned with SHA256 hashes inside the multi-stage Dockerfile.

To build the image locally:

```bash
docker build -t solodolobolo/mosquitto:latest .

```