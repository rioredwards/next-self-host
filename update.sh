#!/bin/bash

# Script Vars
REPO_URL="https://github.com/leerob/next-self-host.git"
APP_DIR=~/myapp

# Pull the latest changes from the Git repository
if [ -d "$APP_DIR" ]; then
	echo "Pulling latest changes from the repository..."
	cd $APP_DIR
	git pull origin main
else
	echo "Cloning repository from $REPO_URL..."
	git clone $REPO_URL $APP_DIR
	cd $APP_DIR
fi

# Build and restart the Docker containers from the app directory (~/myapp)
echo "Rebuilding and restarting Docker containers..."
# Determine which docker-compose command to use (plugin or standalone)
if docker compose version &>/dev/null; then
	DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
	DOCKER_COMPOSE_CMD="docker-compose"
else
	echo "Docker Compose not found. Exiting."
	exit 1
fi

sudo $DOCKER_COMPOSE_CMD down
sudo $DOCKER_COMPOSE_CMD up --build -d

# Check if Docker Compose started correctly
if ! sudo $DOCKER_COMPOSE_CMD ps | grep "Up"; then
	echo "Docker containers failed to start. Check logs with '$DOCKER_COMPOSE_CMD logs'."
	exit 1
fi

# Output final message
echo "Update complete. Your Next.js app has been deployed with the latest changes."
