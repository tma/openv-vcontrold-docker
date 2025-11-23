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
- **Periodic publish**: Every `INTERVAL` seconds, commands listed in `COMMANDS` are grouped (max `MAX_LENGTH` characters per `vclient` call) and their JSON output is flattened into MQTT topics `${MQTT_TOPIC}/info/<command>` with the numeric value as the payload.
- **Request/response (opt-in)**: When `MQTT_SUBSCRIBE=true`, the container listens on `${MQTT_TOPIC}/request`. Each incoming payload is treated as a `vclient` command; the JSON response is written to `${MQTT_TOPIC}/response`.

## Configuration & Environment Variables
| Variable | Default | Description |
| --- | --- | --- |
| `USB_DEVICE` | `/dev/vitocal` | Path inside the container pointing at the Optolink/FTDI serial device. Bind your host device to this path via `--device` or Compose `devices:` mapping. |
| `MAX_LENGTH` | `512` | Maximum character length of a comma-separated `COMMANDS` batch passed to `vclient`. Prevents oversized requests. |
| `MQTT_ACTIVE` | `false` | Enable periodic polling + MQTT publishing loop. Set to `true` to activate `publish.sh`. |
| `MQTT_SUBSCRIBE` | `false` | When `true`, `subscribe.sh` listens for `${MQTT_TOPIC}/request` commands and publishes responses. Requires `MQTT_ACTIVE=true`. |
| `MQTT_HOST` | _(required when MQTT active)_ | Hostname/IP of your MQTT broker. |
| `MQTT_PORT` | `1883` | MQTT broker TCP port. |
| `MQTT_TOPIC` | _(required when MQTT active)_ | Base topic prefix for publish/subscribe traffic (e.g. `vcontrold`). Subtopics `info/`, `request`, `response` are appended automatically. |
| `MQTT_USER` | empty | Username for brokers that enforce authentication. Leave empty for anonymous access. |
| `MQTT_PASSWORD` | empty | Password corresponding to `MQTT_USER`. |
| `MQTT_TLS` | `false` | Enable TLS for MQTT connections. Set to `true` (and typically `MQTT_PORT=8883`) when your broker requires TLS. |
| `MQTT_CAFILE` | empty | Absolute path to a CA certificate file used to verify the broker when TLS is enabled. |
| `MQTT_CAPATH` | empty | Directory containing CA certificates (alternative to `MQTT_CAFILE`). |
| `MQTT_CERTFILE` | empty | Client certificate for mutual TLS authentication. |
| `MQTT_KEYFILE` | empty | Private key matching `MQTT_CERTFILE`. |
| `MQTT_TLS_VERSION` | empty | Optional TLS protocol hint (e.g. `tlsv1.2`). |
| `MQTT_TLS_INSECURE` | `false` | Skip certificate validation when `true`. Useful for testing only. |
| `INTERVAL` | `60` | Seconds between telemetry polls when `MQTT_ACTIVE=true`. |
| `COMMANDS` | empty | Comma-separated list of vcontrold command names to poll (example: `getTempWWObenIst,getTempWWsoll`). Each name must exist in your `vcontrold.xml`. |

The compose file in this repo ships sensible defaults (MQTT enabled, command list populated). Override anything via your own `.env` file or `environment:` block.

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

### Reference `docker-compose.yaml`

```yaml
version: '3.1'
services:
   vcontrold:
      build: .
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
