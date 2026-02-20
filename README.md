# EVerest Multi-Charger Simulator

Standalone setup for running multiple EVerest OCPP chargers with Node-RED UIs for CSMS testing.

## What This Is

Run multiple simulated EV chargers that connect to your CSMS (Charging Station Management System) for testing. Each charger has:
- ✅ Full OCPP 1.6/2.0.1 support
- ✅ Node-RED UI for control (plug in car, start charging, etc.)
- ✅ Isolated MQTT broker
- ✅ Configurable ChargePointId and CSMS endpoint

Perfect for load testing, integration testing, and development.

## Quick Start

### 1. Clone This Repo

```bash
git clone https://github.com/eliodecolli/medinilla-everest-sim-docker.git
cd medinilla-everest-sim-docker
```

### 2. Create Your Config

```bash
cp config/multi-charger.env.example config/multi-charger.env
nano config/multi-charger.env
```

Minimum required settings:
```bash
IMAGE_NAME="eliodecolli/everest-multi-sim"
CSMS_URL="ws://192.168.1.100:9000/ocpp"
NUM_CHARGERS=5
```

### 3. Run Setup

```bash
chmod +x setup-multi-chargers.sh
./setup-multi-chargers.sh
```

### 4. Start Chargers

```bash
cd multi-charger-sim
./start.sh
```

### 5. Access UIs

Open in browser:
- Charger 1: http://localhost:1880/ui
- Charger 2: http://localhost:1881/ui
- Charger 3: http://localhost:1882/ui
- etc.

## Requirements

- Docker + Docker Compose V2
- Pre-built Docker image on Docker Hub, or everest-core repo for local build

## Configuration

All settings in `config/multi-charger.env`:

```bash
# Docker image (use Docker Hub or build locally)
IMAGE_NAME="eliodecolli/everest-multi-sim"

# Your CSMS endpoint
CSMS_URL="ws://192.168.1.100:9000/ocpp"

# Number of chargers to simulate
NUM_CHARGERS=5

# Charger ID prefix (creates CP_001, CP_002, etc.)
CHARGER_PREFIX="CP_"

# Starting UI port
START_PORT=1880

# OCPP version
OCPP_VERSION="1.6"

# Only needed if building locally:
# EVEREST_CORE_DIR="/path/to/everest-core"
```

## Documentation

- **[README-MULTI-CHARGER.md](README-MULTI-CHARGER.md)** - Detailed configuration guide

## Two Usage Modes

### Mode 1: Docker Hub Image (Recommended)

**Fully standalone** - no everest-core repo needed!

```bash
IMAGE_NAME="eliodecolli/everest-multi-sim"
```

- ✅ Fast: Pull image instead of 30-60 min build
- ✅ Portable: Works anywhere with Docker
- ✅ Small: Only need this repo (~500 KB)

### Mode 2: Local Build

Build from everest-core source:

```bash
IMAGE_NAME="everest-multi-sim"
EVEREST_CORE_DIR="/path/to/everest-core"
```

- ✅ Customizable: Modify EVerest code
- ✅ Latest: Use unreleased features
- ⏱️ Slow: 30-60 minute build time

## Building & Pushing Docker Image

First time setup - build the image once:

```bash
# 1. Clone everest-core (one-time)
git clone https://github.com/EVerest/everest-core.git

# 2. Build image (one-time, 30-60 min)
IMAGE_NAME="everest-multi-sim" EVEREST_CORE_DIR="./everest-core" ./setup-multi-chargers.sh

# 3. Tag and push to Docker Hub (one-time)
docker tag everest-multi-sim:latest <your-dockerhub-username>/everest-multi-sim:latest
docker login
docker push <your-dockerhub-username>/everest-multi-sim:latest
```

Now everyone can use your image without building!

## Project Structure

```
.
├── setup-multi-chargers.sh       # Main setup script
├── config/
│   ├── multi-charger.env.example # Config template
│   └── templates/                # EVerest config templates
│       ├── config-sil-ocpp.yaml
│       ├── ocpp-config.json
│       └── config-sil-dc-flow.json
├── README.md                     # This file
└── README-MULTI-CHARGER.md       # Detailed config guide
```

## Control Scripts

After running `./setup-multi-chargers.sh`, you get:

```bash
cd multi-charger-sim
./start.sh       # Start all chargers
./stop.sh        # Stop all chargers
./restart.sh     # Restart all chargers
./status.sh      # Check status
./logs.sh        # View all logs
./logs.sh 3      # View charger 3 logs only
./open-uis.sh    # Open all UIs in browser
```

## Troubleshooting

**Port conflicts:**
```bash
sudo lsof -ti:1880 | xargs sudo kill -9
cd multi-charger-sim && ./restart.sh
```

**Image not found:**
- Check `IMAGE_NAME` in config
- Make sure image is pushed: `docker push eliodecolli/everest-multi-sim:latest`
- Or build locally: Set `EVEREST_CORE_DIR`

**Chargers not connecting:**
- Check CSMS is running
- Verify `CSMS_URL` format: `ws://IP:PORT/path`
- View logs: `cd multi-charger-sim && ./logs.sh`

## Use Cases

- 🧪 **Load Testing**: Simulate 50+ chargers connecting simultaneously
- 🔗 **Integration Testing**: Test CSMS message handling
- 🚀 **Development**: Develop CSMS without physical hardware
- 📊 **Demos**: Show CSMS capabilities with multiple chargers
- ✅ **CI/CD**: Automated testing pipelines

## License

Based on EVerest (Apache 2.0)

## Contributing

Issues and PRs welcome!

## Links

- [EVerest Project](https://github.com/EVerest/everest-core)
- [OCPP Specification](https://www.openchargealliance.org/)
