#!/bin/bash
# Setup script for multiple EVerest charger simulations with Node-RED UIs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

EVEREST_CORE_DIR=""
DOCKER_BUILD_DIR="$EVEREST_CORE_DIR/applications/utils/docker/everest-docker-image"

echo -e "${GREEN}=== EVerest Multi-Charger Simulation Setup ===${NC}\n"

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration from file
CONFIG_FILE="${SCRIPT_DIR}/config/multi-charger.env"
if [ ! -f "$CONFIG_FILE" ]; then
    # Try old location for backwards compatibility
    CONFIG_FILE="${SCRIPT_DIR}/multi-charger.env"
fi

if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}Loading configuration from $CONFIG_FILE${NC}"
    source "$CONFIG_FILE"
else
    echo -e "${RED}Error: No config file found.${NC}"
    echo -e "${YELLOW}Copy config/multi-charger.env.example to config/multi-charger.env and customize it.${NC}"
    exit 1
fi

# Determine config source (templates or everest-core repo)
TEMPLATES_DIR="${SCRIPT_DIR}/config/templates"
USE_TEMPLATES=false

if [ -d "$TEMPLATES_DIR" ] && [ -f "$TEMPLATES_DIR/config-sil-ocpp.yaml" ]; then
    echo -e "${GREEN}Using config templates from $TEMPLATES_DIR${NC}"
    USE_TEMPLATES=true
    CONFIG_SOURCE="$TEMPLATES_DIR"
elif [ -d "$EVEREST_CORE_DIR" ]; then
    echo -e "${GREEN}Using configs from EVerest repo: $EVEREST_CORE_DIR${NC}"
    CONFIG_SOURCE="$EVEREST_CORE_DIR"
else
    echo -e "${RED}Error: No config source found!${NC}"
    echo -e "${YELLOW}Options:${NC}"
    echo "  1. Templates are missing - they should be in: $TEMPLATES_DIR"
    echo "  2. Set EVEREST_CORE_DIR to point to everest-core repository"
    exit 1
fi

# Check if we can build (only needed for local builds)
if [[ "$IMAGE_NAME" != *"/"* ]]; then
    # Local build - need everest-core repo
    if [ ! -d "$EVEREST_CORE_DIR" ]; then
        echo -e "${RED}Error: Building locally requires everest-core directory${NC}"
        echo -e "${YELLOW}Set EVEREST_CORE_DIR in config/multi-charger.env or use Docker Hub image${NC}"
        exit 1
    fi
fi

# Validate inputs
if [[ -z "$CSMS_URL" ]]; then
    echo -e "${RED}Error: CSMS URL is required${NC}"
    exit 1
fi

if ! [[ "$NUM_CHARGERS" =~ ^[0-9]+$ ]] || [ "$NUM_CHARGERS" -lt 1 ]; then
    echo -e "${RED}Error: Number of chargers must be a positive integer${NC}"
    exit 1
fi

if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Starting port must be a number${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Configuration:${NC}"
echo "  Image: $IMAGE_NAME"
echo "  CSMS URL: $CSMS_URL"
echo "  Number of chargers: $NUM_CHARGERS"
echo "  Charger ID prefix: $CHARGER_PREFIX"
echo "  UI ports: $START_PORT - $((START_PORT + NUM_CHARGERS - 1))"
echo "  OCPP Version: $OCPP_VERSION"
echo ""

echo -e "${GREEN}Using config from $CONFIG_FILE${NC}\n"

# Create directory structure
MULTI_CHARGER_DIR="./multi-charger-sim"
mkdir -p "$MULTI_CHARGER_DIR/configs"
mkdir -p "$MULTI_CHARGER_DIR/nodered-data"
mkdir -p "$MULTI_CHARGER_DIR/logs"

echo -e "\n${BLUE}Step 1: Building EVerest Docker image...${NC}"
echo "This may take 10-15 minutes on first build (cached after that)"
echo ""

# Determine config file based on OCPP version
if [[ "$OCPP_VERSION" == "2.0.1" ]]; then
    BASE_CONFIG="$EVEREST_CORE_DIR/config/config-sil-ocpp201.yaml"
    if [ ! -f "$BASE_CONFIG" ]; then
        BASE_CONFIG="$EVEREST_CORE_DIR/config/config-sil.yaml"
    fi
else
    BASE_CONFIG="$EVEREST_CORE_DIR/config/config-sil.yaml"
fi

# Check if image already exists (only build if it's the local name, not a registry image)
if [[ "$IMAGE_NAME" == *"/"* ]]; then
    echo -e "${BLUE}Using registry image: $IMAGE_NAME${NC}"
    echo "Pulling image..."
    docker pull "$IMAGE_NAME:latest" || echo -e "${YELLOW}Warning: Could not pull image, will use local if available${NC}"
elif docker images | grep -q "$IMAGE_NAME"; then
    echo -e "${YELLOW}Image $IMAGE_NAME already exists. Skipping build.${NC}"
    echo "To rebuild, run: docker rmi $IMAGE_NAME"
else
    # Build the base EVerest image
    ORIGINAL_DIR=$(pwd)
    cd "$DOCKER_BUILD_DIR"
    ./build.sh --conf "$BASE_CONFIG" --name "$IMAGE_NAME" --branch main

    # Load the built image
    TARBALL=$(ls -t ${IMAGE_NAME}*.tar.gz 2>/dev/null | head -1)
    if [ -n "$TARBALL" ]; then
        echo -e "${GREEN}Loading image from $TARBALL...${NC}"
        docker load < "$TARBALL"
    else
        echo -e "${RED}Error: Could not find built image tarball${NC}"
        exit 1
    fi

    cd "$ORIGINAL_DIR"
fi

echo -e "\n${BLUE}Step 2: Creating Docker Compose configuration...${NC}"

# Create docker-compose.yml
cat > "$MULTI_CHARGER_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
EOF

# Determine OCPP module name
if [[ "$OCPP_VERSION" == "2.0.1" ]]; then
    OCPP_MODULE="OCPP201"
else
    OCPP_MODULE="OCPP"
fi

# Generate charger services and configs
for i in $(seq 1 $NUM_CHARGERS); do
    CHARGER_ID="${CHARGER_PREFIX}$(printf "%03d" $i)"
    SERVICE_NAME="charger_$i"
    NODERED_SERVICE="nodered_$i"
    UI_PORT=$((START_PORT + i - 1))

    echo -e "${YELLOW}Configuring $CHARGER_ID (UI port: $UI_PORT)...${NC}"

    # Create Node-RED data directory for this charger
    mkdir -p "$MULTI_CHARGER_DIR/nodered-data/charger-$i"

    # Copy real DC charging flow
    if [ "$USE_TEMPLATES" = true ]; then
        FLOW_SOURCE="$CONFIG_SOURCE/config-sil-dc-flow.json"
    else
        FLOW_SOURCE="$CONFIG_SOURCE/config/nodered/config-sil-dc-flow.json"
    fi

    if [ -f "$FLOW_SOURCE" ]; then
        cp "$FLOW_SOURCE" "$MULTI_CHARGER_DIR/nodered-data/charger-$i/flows.json"
        # Update MQTT broker references to point to this charger's isolated MQTT
        sed -i "s/\"broker\":\"mqtt-server\"/\"broker\":\"mqtt_$i\"/g" "$MULTI_CHARGER_DIR/nodered-data/charger-$i/flows.json"
        sed -i "s/\"broker\":\"mqtt\"/\"broker\":\"mqtt_$i\"/g" "$MULTI_CHARGER_DIR/nodered-data/charger-$i/flows.json"
        sed -i "s/mqtt-server/mqtt_$i/g" "$MULTI_CHARGER_DIR/nodered-data/charger-$i/flows.json"
    else
        echo -e "${YELLOW}Warning: DC flow not found at $FLOW_SOURCE${NC}"
        echo "[]" > "$MULTI_CHARGER_DIR/nodered-data/charger-$i/flows.json"
    fi

    # Add MQTT broker for this charger (isolated, no host port binding)
    cat >> "$MULTI_CHARGER_DIR/docker-compose.yml" <<EOF
  mqtt_$i:
    image: ghcr.io/everest/everest-dev-environment/mosquitto:docker-images-v0.2.0
    container_name: mqtt-charger-$i
    networks:
      - charger-network-$i

EOF

    # Add Node-RED service
    cat >> "$MULTI_CHARGER_DIR/docker-compose.yml" <<EOF
  $NODERED_SERVICE:
    image: ghcr.io/everest/everest-dev-environment/nodered:docker-images-v0.2.0
    container_name: nodered-charger-$i
    ports:
      - "${UI_PORT}:1880"
    volumes:
      - ./nodered-data/charger-$i:/data
    environment:
      - TZ=Europe/Berlin
      - NODE_RED_ENABLE_SAFE_MODE=false
      - MQTT_BROKER=mqtt_$i
      - MQTT_PORT=1883
    depends_on:
      - mqtt_$i
    networks:
      - charger-network-$i

EOF

    # Add EVerest charger service
    cat >> "$MULTI_CHARGER_DIR/docker-compose.yml" <<EOF
  $SERVICE_NAME:
    image: ${IMAGE_NAME}:latest
    container_name: charger-$i
    depends_on:
      - mqtt_$i
      - $NODERED_SERVICE
    volumes:
      - ./configs/charger-$i.yaml:/opt/everest/config/config.yaml:ro
      - ./configs/ocpp-$i.json:/opt/everest/config/ocpp-$i.json:ro
      - ./logs:/opt/everest/logs
    environment:
      - CHARGER_ID=$CHARGER_ID
    command: ["/opt/everest/bin/manager", "--conf", "/opt/everest/config/config.yaml"]
    networks:
      - charger-network-$i

EOF

    # Copy real EVerest OCPP config
    if [ "$USE_TEMPLATES" = true ]; then
        cp "$CONFIG_SOURCE/config-sil-ocpp.yaml" "$MULTI_CHARGER_DIR/configs/charger-$i.yaml"
    else
        cp "$CONFIG_SOURCE/config/config-sil-ocpp.yaml" "$MULTI_CHARGER_DIR/configs/charger-$i.yaml"
    fi

    # Update OCPP config path to point to charger-specific JSON
    sed -i 's|ChargePointConfigPath:.*|ChargePointConfigPath: /opt/everest/config/ocpp-'$i'.json|' "$MULTI_CHARGER_DIR/configs/charger-$i.yaml"

    # Add settings section with MQTT broker configuration
    cat >> "$MULTI_CHARGER_DIR/configs/charger-$i.yaml" <<SETTINGS_EOF

settings:
  mqtt_broker_host: mqtt_$i
  mqtt_broker_port: 1883
  telemetry_enabled: false
SETTINGS_EOF

    # Create OCPP JSON config for this charger
    if [ "$USE_TEMPLATES" = true ]; then
        cp "$CONFIG_SOURCE/ocpp-config.json" "$MULTI_CHARGER_DIR/configs/ocpp-$i.json"
    else
        cp "$CONFIG_SOURCE/lib/everest/ocpp/config/v16/config-docker.json" "$MULTI_CHARGER_DIR/configs/ocpp-$i.json"
    fi

    # Update OCPP JSON with charger-specific settings
    sed -i "s/\"ChargePointId\": \".*\"/\"ChargePointId\": \"$CHARGER_ID\"/" "$MULTI_CHARGER_DIR/configs/ocpp-$i.json"
    sed -i "s|\"CentralSystemURI\": \".*\"|\"CentralSystemURI\": \"$CSMS_URL\"|" "$MULTI_CHARGER_DIR/configs/ocpp-$i.json"
    sed -i "s/\"ChargeBoxSerialNumber\": \".*\"/\"ChargeBoxSerialNumber\": \"SN-$CHARGER_ID\"/" "$MULTI_CHARGER_DIR/configs/ocpp-$i.json"

done

# Add networks section to docker-compose
cat >> "$MULTI_CHARGER_DIR/docker-compose.yml" <<EOF

networks:
EOF

# Add per-charger networks
for i in $(seq 1 $NUM_CHARGERS); do
    cat >> "$MULTI_CHARGER_DIR/docker-compose.yml" <<EOF
  charger-network-$i:
    driver: bridge
EOF
done

echo -e "\n${BLUE}Step 3: Creating control scripts...${NC}"

# Create start script
cat > "$MULTI_CHARGER_DIR/start.sh" <<'BASH_EOF'
#!/bin/bash
echo "Starting multi-charger simulation..."
docker compose up -d
echo ""
echo "✅ Chargers started!"
echo ""
echo "📱 Access UIs:"
BASH_EOF

for i in $(seq 1 $NUM_CHARGERS); do
    CHARGER_ID="${CHARGER_PREFIX}$(printf "%03d" $i)"
    UI_PORT=$((START_PORT + i - 1))
    echo "echo \"   $CHARGER_ID: http://localhost:$UI_PORT/ui\"" >> "$MULTI_CHARGER_DIR/start.sh"
done

cat >> "$MULTI_CHARGER_DIR/start.sh" <<'BASH_EOF'
echo ""
echo "📊 View logs:"
echo "   ./logs.sh          # All chargers"
echo "   ./logs.sh 1        # Charger 1 only"
echo ""
echo "🛑 Stop:"
echo "   ./stop.sh"
BASH_EOF
chmod +x "$MULTI_CHARGER_DIR/start.sh"

# Create other scripts
cat > "$MULTI_CHARGER_DIR/stop.sh" <<'EOF'
#!/bin/bash
echo "Stopping multi-charger simulation..."
docker compose down
echo "Stopped."
EOF
chmod +x "$MULTI_CHARGER_DIR/stop.sh"

cat > "$MULTI_CHARGER_DIR/logs.sh" <<'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Showing logs for all chargers..."
    docker compose logs -f
else
    echo "Showing logs for charger $1..."
    docker compose logs -f charger_$1
fi
EOF
chmod +x "$MULTI_CHARGER_DIR/logs.sh"

cat > "$MULTI_CHARGER_DIR/restart.sh" <<'EOF'
#!/bin/bash
echo "Restarting multi-charger simulation..."
docker compose restart
EOF
chmod +x "$MULTI_CHARGER_DIR/restart.sh"

cat > "$MULTI_CHARGER_DIR/status.sh" <<'EOF'
#!/bin/bash
docker compose ps
EOF
chmod +x "$MULTI_CHARGER_DIR/status.sh"

cat > "$MULTI_CHARGER_DIR/open-uis.sh" <<'EOF'
#!/bin/bash
echo "Opening charger UIs in browser..."
EOF

for i in $(seq 1 $NUM_CHARGERS); do
    UI_PORT=$((START_PORT + i - 1))
    echo "xdg-open http://localhost:$UI_PORT/ui 2>/dev/null || open http://localhost:$UI_PORT/ui 2>/dev/null &" >> "$MULTI_CHARGER_DIR/open-uis.sh"
done

echo "echo 'UIs opened in browser'" >> "$MULTI_CHARGER_DIR/open-uis.sh"
chmod +x "$MULTI_CHARGER_DIR/open-uis.sh"

# Create README
cat > "$MULTI_CHARGER_DIR/README.md" <<EOF
# Multi-Charger Simulation with UIs

Runs **$NUM_CHARGERS chargers** simultaneously with Node-RED UIs.

## Configuration

- **CSMS URL**: $CSMS_URL
- **Charger IDs**: ${CHARGER_PREFIX}001 through ${CHARGER_PREFIX}$(printf "%03d" $NUM_CHARGERS)
- **OCPP Version**: $OCPP_VERSION
- **UI Ports**: $START_PORT - $((START_PORT + NUM_CHARGERS - 1))
- **Docker Image**: $IMAGE_NAME

## Quick Start

\`\`\`bash
./start.sh       # Start all chargers
./open-uis.sh    # Open all UIs in browser
./status.sh      # Check status
./logs.sh        # View all logs
./stop.sh        # Stop all chargers
\`\`\`

## Individual Charger UIs

EOF

for i in $(seq 1 $NUM_CHARGERS); do
    CHARGER_ID="${CHARGER_PREFIX}$(printf "%03d" $i)"
    UI_PORT=$((START_PORT + i - 1))
    echo "- **$CHARGER_ID**: http://localhost:$UI_PORT/ui" >> "$MULTI_CHARGER_DIR/README.md"
done

cat >> "$MULTI_CHARGER_DIR/README.md" <<'EOF'

## Rebuild EVerest Image

If you need to rebuild the EVerest image:

\`\`\`bash
docker rmi everest-multi-sim
cd ..
./setup-multi-chargers.sh
\`\`\`

## Troubleshooting

### Chargers not connecting to CSMS

Check logs:
\`\`\`bash
./logs.sh 1
\`\`\`

Update CSMS URL in \`configs/charger-N.yaml\` and restart:
\`\`\`bash
./restart.sh
\`\`\`

### Port conflicts

\`\`\`bash
sudo lsof -ti:1880 | xargs sudo kill -9
./restart.sh
\`\`\`

### Reset everything

\`\`\`bash
./stop.sh
docker compose down -v
./start.sh
\`\`\`
EOF

echo -e "\n${GREEN}=== Setup Complete! ===${NC}\n"
echo -e "Multi-charger simulation created in: ${YELLOW}$MULTI_CHARGER_DIR${NC}\n"
echo "Next steps:"
echo "  cd $MULTI_CHARGER_DIR"
echo "  ./start.sh"
echo "  ./open-uis.sh"
echo ""
echo -e "${YELLOW}Chargers and UIs:${NC}"
for i in $(seq 1 $NUM_CHARGERS); do
    CHARGER_ID="${CHARGER_PREFIX}$(printf "%03d" $i)"
    UI_PORT=$((START_PORT + i - 1))
    echo "  $CHARGER_ID - http://localhost:$UI_PORT/ui"
done
echo ""
echo -e "${YELLOW}Note:${NC} Make sure your CSMS is running at: $CSMS_URL"
