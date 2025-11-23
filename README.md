# openv-vcontrold-docker

Containerized build of [openv/vcontrold](https://github.com/openv/vcontrold) with optional MQTT telemetry so you can query a Viessmann heating controller from any machine that runs Docker. The image bundles vcontrold, the Viessmann XML definitions, and helper scripts for scheduled polls as well as on-demand requests over MQTT.

## Highlights
- Multi-arch image (amd64/arm64/armv7/armv6) built directly from upstream `.deb` packages.
- Ships minimal runtime (Debian bookworm-slim) plus `mosquitto-clients` and `jq` for MQTT + JSON parsing.
- Opinionated entrypoint that keeps `vcontrold` alive, batches `vclient` commands, and publishes values to MQTT topics.
- Optional request/response bridge via MQTT subscription so you can run ad-hoc `vclient` commands remotely.

## Repository Layout
- `Dockerfile`: multi-stage build that downloads and installs the requested vcontrold release.
- `app/`: startup + MQTT helper scripts executed inside the container.
- `config/`: sample `vcontrold.xml` and device definitions (`vito.xml`). Mount your own config at runtime.
- `docker-compose.yaml`: reference deployment with device passthrough, config + log volumes, and MQTT settings.

## Prerequisites
- Linux host (or VM) with access to the Viessmann Optolink/FTDI adapter. Map the serial device into the container (see compose file).
- Docker 24.x+ and, if you use the provided stack, Docker Compose V2 (`docker compose`).
- MQTT broker reachable from the container when `MQTTACTIVE=true`.

## Quick Start with Docker Compose
1. Adjust `docker-compose.yaml`:
   - Update the `devices` entry to point at your USB adapter (HOST:/dev/vitocal).
   - Copy your tailored `vcontrold.xml`/`vito.xml` into `config/`.
   - Set the MQTT environment variables (see table below).
2. Launch the stack:
   ```bash
   docker compose up -d
   ```
3. Tail logs or stop the container when needed:
   ```bash
   docker compose logs -f vcontrold
   docker compose down
   ```

On startup, `app/startup.sh` runs `vcontrold`, waits for it to answer `vclient`, and optionally starts the MQTT publisher/subscriber loops.

## MQTT Data Flow
- **Periodic publish**: Every `INTERVAL` seconds, commands listed in `COMMANDS` are grouped (max `MAX_LENGTH` characters per `vclient` call) and their JSON output is flattened into MQTT topics `${MQTTTOPIC}/info/<command>` with the numeric value as the payload.
- **Request/response (opt-in)**: When `MQTTSUBSCRIBE=true`, the container listens on `${MQTTTOPIC}/request`. Each incoming payload is treated as a `vclient` command; the JSON response is written to `${MQTTTOPIC}/response`.

## Configuration & Environment Variables
| Variable | Default | Description |
| --- | --- | --- |
| `USB_DEVICE` | `/dev/vitocal` | Path inside the container pointing at the Optolink/FTDI serial device. Bind your host device to this path via `--device` or Compose `devices:` mapping. |
| `MAX_LENGTH` | `512` | Maximum character length of a comma-separated `COMMANDS` batch passed to `vclient`. Prevents oversized requests. |
| `MQTTACTIVE` | `false` | Enable periodic polling + MQTT publishing loop. Set to `true` to activate `publish.sh`. |
| `MQTTSUBSCRIBE` | `false` | When `true`, `subscribe.sh` listens for `${MQTTTOPIC}/request` commands and publishes responses. Requires `MQTTACTIVE=true`. |
| `MQTTHOST` | _(required when MQTT active)_ | Hostname/IP of your MQTT broker. |
| `MQTTPORT` | `1883` | MQTT broker TCP port. |
| `MQTTTOPIC` | _(required when MQTT active)_ | Base topic prefix for publish/subscribe traffic (e.g. `vcontrold`). Subtopics `info/`, `request`, `response` are appended automatically. |
| `MQTTUSER` | empty | Username for brokers that enforce authentication. Leave empty for anonymous access. |
| `MQTTPASSWORD` | empty | Password corresponding to `MQTTUSER`. |
| `INTERVAL` | `60` | Seconds between telemetry polls when `MQTTACTIVE=true`. |
| `COMMANDS` | empty | Comma-separated list of vcontrold command names to poll (example: `getTempWWObenIst,getTempWWsoll`). Each name must exist in your `vcontrold.xml`. |

The compose file in this repo ships sensible defaults (MQTT enabled, command list populated). Override anything via your own `.env` file or `environment:` block.

## Customizing Configuration
- **XML definitions**: Replace `config/vito.xml` and `config/vcontrold.xml` with ones matching your boiler/heat pump. The container mounts `/config` as a volume and never overwrites files that already exist there.
- **Logging**: Bind-mount a host directory to `/log` (as shown in the sample compose file) to persist `vcontrold` logs.
- **Standalone usage**: If you prefer raw `docker run`, pass the same volumes/devices/env vars manually:
  ```bash
  docker run -d --name vcontrold \
    --device /dev/serial/by-id/<your-ftdi>:/dev/vitocal \
    -v "$PWD/config:/config" -v "$PWD/log:/log" \
    -e MQTTACTIVE=true -e MQTTHOST=10.0.0.1 -e MQTTTOPIC=vcontrold \
    ghcr.io/<your-namespace>/openv-vcontrold-docker:latest
  ```

With Docker Compose or `docker run`, the container stays alive as long as `vcontrold` is healthy and will exit if the daemon stops unexpectedly. Review `docker compose logs vcontrold` for troubleshooting.
