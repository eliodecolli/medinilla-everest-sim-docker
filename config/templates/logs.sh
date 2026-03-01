#!/bin/bash
if [ -z "$1" ]; then
    echo "Showing logs for all chargers..."
    docker compose logs -f
else
    echo "Showing logs for charger $1..."
    docker compose logs -f charger_$1
fi
