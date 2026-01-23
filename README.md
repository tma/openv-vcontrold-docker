**Deprecated in favor of new version keeping permanent connections, see [vcontrold-mqttd](https://github.com/tma/vcontrold-mqttd).**

# vcontrold Docker — Viessmann Heating Controller with MQTT

Containerized build of [openv/vcontrold](https://github.com/openv/vcontrold) with optional MQTT telemetry so you can query a Viessmann heating controller from any machine that runs Docker. The image bundles vcontrold, the Viessmann XML definitions, and helper scripts for scheduled polls as well as on-demand requests over MQTT.

> This project builds upon the excellent work of [@michelde](https://github.com/michelde) and [@Astretowe](https://github.com/Astretowe). See [Credits](#credits) for details.

## Highlights

- Multi-arch image (amd64/arm64/armv7) built directly from upstream `.deb` packages.
- Ships minimal runtime (Debian bookworm-slim) plus `mosquitto-clients` and `jq` for MQTT + JSON parsing.
- Opinionated entrypoint that keeps `vcontrold` alive, batches `vclient` commands, and publishes values to MQTT topics.
- Optional request/response bridge via MQTT subscription so you can run ad-hoc `vclient` commands remotely.

## Repository Layout

- `Dockerfile`: multi-stage build that downloads and installs the requested vcontrold release.
- `app/`: startup + MQTT helper scripts executed inside the container.
- `config/`: example `vcontrold.xml` and device definitions (`vito.xml`). Mount your own config at runtime.
- `.github/workflows/`: CI/CD pipeline for building and publishing Docker images.

## Prerequisites

- Linux host (or VM) with access to the Viessmann Optolink/FTDI adapter. Map the serial device into the container (see compose file).
- Docker 24.x+ and, if you use the provided stack, Docker Compose V2 (`docker compose`).
- MQTT broker reachable from the container when `MQTT_ACTIVE=true`.

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

- **Periodic publish**: Every `INTERVAL` seconds, commands listed in `COMMANDS` are grouped (max `MAX_LENGTH` characters per `vclient` call) and their JSON output is flattened into MQTT topics `${MQTT_TOPIC}/command/<command>` with the numeric value as the payload.
- **Request/response (opt-in)**: When `MQTT_SUBSCRIBE=true`, the container listens on `${MQTT_TOPIC}/request`. Each incoming payload is treated as a `vclient` command; the JSON response is written to `${MQTT_TOPIC}/response`. Multiple commands can be sent in a single request using comma-separated format.

### Multiple Commands in a Single Request

Send multiple commands at once by separating them with commas:

```bash
# Single command
mosquitto_pub -t "vcontrold/request" -m "getTempWWObenIst"
# Response: {"getTempWWObenIst":{"value":48.1}}

# Multiple commands
mosquitto_pub -t "vcontrold/request" -m "getTempWWObenIst,getTempWWsoll"
# Response: {"getTempWWObenIst":{"value":48.1},"getTempWWsoll":{"value":50}}

# Write commands
mosquitto_pub -t "vcontrold/request" -m "set1xWW 2,setTempWWsoll 50"
# Response: {"set1xWW":{"value":"OK"},"setTempWWsoll":{"value":"OK"}}
```

**Error handling**: Errors are returned as vclient outputs them. For invalid commands, vclient outputs error messages on stderr which are included in the response.

## Configuration & Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `USB_DEVICE` | `/dev/vitocal` | Path inside the container pointing at the Optolink/FTDI serial device. Bind your host device to this path via `--device` or Compose `devices:` mapping. |
| `MAX_LENGTH` | `512` | Maximum character length of a comma-separated `COMMANDS` batch passed to `vclient`. Prevents oversized requests. |
| `MQTT_ACTIVE` | `false` | Enable periodic polling + MQTT publishing loop. Set to `true` to activate `publish.sh`. |
| `MQTT_SUBSCRIBE` | `false` | When `true`, `subscribe.sh` listens for `${MQTT_TOPIC}/request` commands and publishes responses. Requires `MQTT_ACTIVE=true`. |
| `MQTT_HOST` | _(required when MQTT active)_ | Hostname/IP of your MQTT broker. |
| `MQTT_PORT` | `1883` | MQTT broker TCP port. |
| `MQTT_TOPIC` | _(required when MQTT active)_ | Base topic prefix for publish/subscribe traffic (e.g. `vcontrold`). Subtopics `command/`, `request`, `response` are appended automatically. |
| `MQTT_USER` | empty | Username for brokers that enforce authentication. Leave empty for anonymous access. |
| `MQTT_PASSWORD` | empty | Password corresponding to `MQTT_USER`. |
| `MQTT_TLS` | `false` | Enable TLS for MQTT connections. Set to `true` (and typically `MQTT_PORT=8883`) when your broker requires TLS. |
| `MQTT_CAFILE` | empty | Absolute path to a CA certificate file used to verify the broker when TLS is enabled. |
| `MQTT_CAPATH` | empty | Directory containing CA certificates (alternative to `MQTT_CAFILE`). |
| `MQTT_CERTFILE` | empty | Client certificate for mutual TLS authentication. |
| `MQTT_KEYFILE` | empty | Private key matching `MQTT_CERTFILE`. |
| `MQTT_TLS_VERSION` | empty | Optional TLS protocol hint (e.g. `tlsv1.2`). |
| `MQTT_TLS_INSECURE` | `false` | Skip certificate validation when `true`. Useful for testing only. |
| `MQTT_CLIENT_ID_PREFIX` | `vcontrold` | Prefix for MQTT client IDs. Useful when running multiple instances against the same broker. |
| `MQTT_TIMEOUT` | `10` | Timeout in seconds for MQTT publish operations. |
| `INTERVAL` | `60` | Seconds between telemetry polls when `MQTT_ACTIVE=true`. |
| `COMMANDS` | empty | Comma-separated list of vcontrold command names to poll (example: `getTempWWObenIst,getTempWWsoll`). Each name must exist in your `vcontrold.xml`. |
| `DEBUG` | `false` | Enable debug logging (see below). |

The reference compose file below ships sensible defaults (MQTT enabled, command list populated). Override anything via your own `.env` file or `environment:` block.

When enabling TLS, mount your certificate material into the container (for example `./certs:/certs`) and point the env vars at those absolute in-container paths (`/certs/ca.crt`, `/certs/client.crt`, etc.).

## Customizing Configuration

- **XML definitions**: Replace `config/vito.xml` and `config/vcontrold.xml` with ones matching your boiler/heat pump. The container mounts `/config` as a volume and never overwrites files that already exist there.
- **Standalone usage**: If you prefer raw `docker run`, pass the same volumes/devices/env vars manually:
  ```bash
  docker run -d --name vcontrold \
    --device /dev/serial/by-id/<your-ftdi>:/dev/vitocal \
      -v "$PWD/config:/config" \
   -e MQTT_ACTIVE=true -e MQTT_HOST=10.0.0.1 -e MQTT_TOPIC=vcontrold \
    ghcr.io/<your-namespace>/openv-vcontrold-docker:latest
  ```

With Docker Compose or `docker run`, the container stays alive as long as `vcontrold` is healthy and will exit if the daemon stops unexpectedly. Review `docker compose logs vcontrold` for troubleshooting.

## Debugging

Set `DEBUG=true` to enable verbose logging. This affects multiple components:

- **vcontrold daemon**: Starts with `--verbose --debug` flags, producing detailed protocol-level output (bytes sent/received on the Optolink interface, command parsing, etc.).
- **Polling loop** (`startup.sh`): Logs each `vclient` command batch before execution and prints the raw JSON response.
- **MQTT publish** (`publish.sh`): Logs the full topic path and payload for every message sent to the broker.
- **MQTT subscribe** (`subscribe.sh`): Logs incoming request payloads received on the `${MQTT_TOPIC}/request` topic.

Example output with `DEBUG=true`:
```
Debug mode enabled
Debug: Executing vclient for: getTempWWObenIst,getTempWWsoll
Debug: vclient response: {"getTempWWObenIst":{"value":48.1},"getTempWWsoll":{"value":50}}
Debug: Publishing to vcontrold/command/getTempWWObenIst: 48.1
Debug: Publishing to vcontrold/command/getTempWWsoll: 50
```

Use this when diagnosing communication issues with your heating controller or MQTT broker.

### Reference `docker-compose.yaml`

```yaml
services:
  vcontrold:
    image: ghcr.io/tma/openv-vcontrold-docker:latest
    container_name: vcontrold
    restart: unless-stopped
    devices:
      - /dev/serial/by-id/usb-FTDI_FT232R_USB_UART_AL00AKZQ-if00-port0:/dev/vitocal:rwm
    environment:
      MQTT_ACTIVE: true
      MQTT_HOST: 10.0.0.1
      MQTT_PORT: 1883
      MQTT_TOPIC: vcontrold
      MQTT_USER: ""
      MQTT_PASSWORD: ""
      # MQTT_TLS: true       # uncomment + set when your broker requires TLS
      # MQTT_PORT: 8883      # typical TLS port
      # MQTT_CAFILE: /certs/ca.crt
      # MQTT_CERTFILE: /certs/client.crt
      # MQTT_KEYFILE: /certs/client.key
      INTERVAL: 30
      COMMANDS: "getTempWWObenIst,getTempWWsoll,getNeigungHK1"
    volumes:
      - ./config:/config
      # - ./certs:/certs:ro   # mount TLS material if needed
```

## Credits

This project is a fork that builds on prior work:

- **[@michelde](https://github.com/michelde)** — Original [openv-vcontrold-docker](https://github.com/michelde/openv-vcontrold-docker) implementation that established the container approach for vcontrold.
- **[@Astretowe](https://github.com/Astretowe)** — [Fork](https://github.com/Astretowe/openv-vcontrold-docker) with additional improvements and MQTT enhancements.

Thank you both for your contributions to the open-source Viessmann/OpenV community!
