# Multi-Charger Setup Guide

Simple, automated setup for running multiple EVerest chargers with Node-RED UIs.

## Quick Start

### 1. Create Your Config File

```bash
cp config/multi-charger.env.example config/multi-charger.env
nano config/multi-charger.env  # Edit with your settings
```

### 2. Run Setup

```bash
./setup-multi-chargers.sh
```

That's it! No prompts, no questions. It reads everything from `multi-charger.env`.

### 3. Start Chargers

```bash
cd multi-charger-sim
./start.sh
```

## Configuration File (`multi-charger.env`)

```bash
# Docker Image - Use local build or Docker Hub image
IMAGE_NAME="eliodecolli/everest-multi-sim"         # Pull from Docker Hub (recommended)
# IMAGE_NAME="everest-multi-sim"                  # Build locally (needs EVEREST_CORE_DIR)

# Your CSMS endpoint
CSMS_URL="ws://192.168.1.100:9000/ocpp"

# How many chargers to simulate
NUM_CHARGERS=5

# Charger ID prefix (creates CP_001, CP_002, etc.)
CHARGER_PREFIX="CP_"

# Starting port for Node-RED UIs (1880, 1881, 1882...)
START_PORT=1880

# OCPP version
OCPP_VERSION="1.6"

# EVerest source repository path
# ONLY needed if building locally (IMAGE_NAME without "/")
# Skip this if using Docker Hub image
EVEREST_CORE_DIR="/path/to/everest-core"

# Output directory (where configs are generated)
MULTI_CHARGER_DIR="./multi-charger-sim"
```

## Using Docker Hub Image (Recommended - No EVerest Repo Needed!)

Instead of building locally (30-60 minutes), use a pre-built image from Docker Hub.

**This approach doesn't require cloning the everest-core repository at all!**

### 1. Build and Push (One Time)

```bash
# Build the image
./setup-multi-chargers.sh  # With IMAGE_NAME="everest-multi-sim"

# Tag and push to Docker Hub
docker tag everest-multi-sim:latest <your-dockerhub-username>/everest-multi-sim:latest
docker push <your-dockerhub-username>/everest-multi-sim:latest
```

### 2. Update Config

Edit `multi-charger.env`:
```bash
IMAGE_NAME="<your-dockerhub-username>/everest-multi-sim"
```

### 3. Use on Any Machine (No EVerest Repo Needed!)

On a fresh machine:

```bash
# Clone just for configs (lightweight - no build needed)
git clone --depth 1 https://github.com/EVerest/everest-core.git
cd everest-core/applications/dev-environment
# Or download setup script to your preferred location

# Create config with your Docker Hub image
cat > config/multi-charger.env <<EOF
IMAGE_NAME="<your-dockerhub-username>/everest-multi-sim"
CSMS_URL="ws://192.168.1.100:9000/ocpp"
NUM_CHARGERS=5
CHARGER_PREFIX="CP_"
START_PORT=1880
OCPP_VERSION="1.6"
EOF

# Run (pulls from Docker Hub, no 30-60min build!)
./setup-multi-chargers.sh
cd multi-charger-sim
./start.sh
```

**Note:** Even when using a Docker Hub image, you need `everest-core` repo for:
- Config templates (config-sil-ocpp.yaml, OCPP JSON)
- Node-RED flows (config-sil-dc-flow.json)

But you don't need to **build** it - just clone it (`--depth 1` for faster clone).

**Time savings:** 5 minutes (clone) vs 60 minutes (clone + build)

## Examples

### Local Development
```bash
IMAGE_NAME="everest-multi-sim"
CSMS_URL="ws://localhost:9000/ocpp"
NUM_CHARGERS=3
CHARGER_PREFIX="DEV_"
```

### Production Testing
```bash
IMAGE_NAME="mycompany/everest-sim"
CSMS_URL="ws://csms.production.com:443/ocpp"
NUM_CHARGERS=50
CHARGER_PREFIX="PROD_"
START_PORT=2000
```

### Multiple Environments

Create different config files:
```bash
cp multi-charger.env multi-charger-dev.env
cp multi-charger.env multi-charger-prod.env

# Use specific config:
CONFIG_FILE=multi-charger-dev.env ./setup-multi-chargers.sh
```

## File Structure

```
~/root-folder/
├── multi-charger.env              # Your config (git ignored)
├── multi-charger.env.example      # Template
├── setup-multi-chargers.sh        # Setup script
├── everest-core/                  # EVerest source
└── multi-charger-sim/             # Generated setup
    ├── configs/
    │   ├── charger-1.yaml
    │   ├── ocpp-1.json
    │   └── ...
    ├── docker-compose.yml
    ├── start.sh
    ├── stop.sh
    └── ...
```

## Tips

- **Version Control**: Add `multi-charger.env` to `.gitignore`, commit `multi-charger.env.example`
- **Multiple Setups**: Create different env files for different test scenarios
- **CI/CD**: Use env files in automation pipelines
- **Docker Hub**: Share your built image with team members to skip building

## Troubleshooting

**No config file found:**
- Make sure `config/multi-charger.env` exists (copy from `config/multi-charger.env.example`)
- Check file permissions: `chmod 644 config/multi-charger.env`

**Image not found:**
- Make sure the image is available: `docker pull eliodecolli/everest-multi-sim:latest`
- Or build locally: set `IMAGE_NAME="everest-multi-sim"` and `EVEREST_CORE_DIR`
