#!/bin/bash

# Env Vars
POSTGRES_USER="myuser"
POSTGRES_PASSWORD=$(openssl rand -base64 12) # Generate a random 12-character password
POSTGRES_DB="mydatabase"
SECRET_KEY="my-secret"          # for the demo app
NEXT_PUBLIC_SAFE_KEY="safe-key" # for the demo app
# Cloudflare Tunnel will handle external routing
# Configure your tunnel domain in Cloudflare dashboard after running this script

# Script Vars
REPO_URL="https://github.com/leerob/next-self-host.git"
APP_DIR=~/myapp
SWAP_SIZE="1G"  # Swap size of 1GB
PI_ARCH="arm64" # aarch64 (ARM64)
DOCKER_ARCH=$PI_ARCH
CLOUDFLARED_ARCH=$PI_ARCH

# Update package list and upgrade existing packages
sudo apt update && sudo apt upgrade -y

# Add Swap Space (only if it doesn't already exist)
if [ ! -f /swapfile ]; then
	echo "Adding swap space..."
	sudo fallocate -l $SWAP_SIZE /swapfile
	sudo chmod 600 /swapfile
	sudo mkswap /swapfile
	sudo swapon /swapfile
	# Make swap permanent
	echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
else
	echo "Swap file already exists, skipping..."
fi

# Install Docker (Debian/Raspberry Pi OS compatible method)
if ! command -v docker &>/dev/null; then
	echo "Installing Docker..."
	# Install prerequisites
	sudo apt install -y ca-certificates curl gnupg

	# Detect OS (Debian or Ubuntu)
	if [ -f /etc/debian_version ]; then
		OS_ID="debian"
		OS_CODENAME=$(lsb_release -cs)
	else
		OS_ID="ubuntu"
		OS_CODENAME=$(lsb_release -cs)
	fi

	# Add Docker's official GPG key (modern method, not apt-key)
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	sudo chmod a+r /etc/apt/keyrings/docker.gpg

	# Add Docker repository
	echo "deb [arch=$DOCKER_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

	sudo apt update
	sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
	echo "Docker already installed."
fi

# Fix Docker IPv6 issue: configure Docker and system to use IPv4
sudo mkdir -p /etc/docker
echo '{"ipv6": false, "fixed-cidr-v6": "", "dns": ["8.8.8.8", "8.8.4.4"]}' | sudo tee /etc/docker/daemon.json >/dev/null

# Configure system to prefer IPv4 for DNS lookups
echo "precedence ::ffff:0:0/96  100" | sudo tee -a /etc/gai.conf >/dev/null 2>&1 || echo "precedence ::ffff:0:0/96  100" | sudo tee /etc/gai.conf >/dev/null

# Update DNS to use Google DNS (returns IPv4 addresses)
if [ -f /etc/resolv.conf ] && ! grep -q "8.8.8.8" /etc/resolv.conf; then
	sudo sed -i '1inameserver 8.8.8.8' /etc/resolv.conf
	sudo sed -i '1inameserver 8.8.4.4' /etc/resolv.conf
fi

# Install Docker Compose standalone (if plugin version is not available)
if ! docker compose version &>/dev/null 2>&1; then
	if ! command -v docker-compose &>/dev/null; then
		echo "Installing Docker Compose standalone..."
		sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
		sudo chmod +x /usr/local/bin/docker-compose

		# Verify installation
		if ! docker-compose --version &>/dev/null; then
			echo "Docker Compose installation failed. Exiting."
			exit 1
		fi
	else
		echo "Docker Compose standalone already available."
	fi
else
	echo "Docker Compose plugin already available."
fi

# Ensure Docker starts on boot and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Clone the Git repository
if [ -d "$APP_DIR" ]; then
	echo "Directory $APP_DIR already exists. Pulling latest changes..."
	cd $APP_DIR && git pull
else
	echo "Cloning repository from $REPO_URL..."
	git clone $REPO_URL $APP_DIR
	cd $APP_DIR
fi

# For Docker internal communication ("db" is the name of Postgres container)
DATABASE_URL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@db:5432/$POSTGRES_DB"

# For external tools (like Drizzle Studio)
DATABASE_URL_EXTERNAL="postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:5432/$POSTGRES_DB"

# Create the .env file inside the app directory (~/myapp/.env)
echo "POSTGRES_USER=$POSTGRES_USER" >"$APP_DIR/.env"
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >>"$APP_DIR/.env"
echo "POSTGRES_DB=$POSTGRES_DB" >>"$APP_DIR/.env"
echo "DATABASE_URL=$DATABASE_URL" >>"$APP_DIR/.env"
echo "DATABASE_URL_EXTERNAL=$DATABASE_URL_EXTERNAL" >>"$APP_DIR/.env"

# These are just for the demo of env vars
echo "SECRET_KEY=$SECRET_KEY" >>"$APP_DIR/.env"
echo "NEXT_PUBLIC_SAFE_KEY=$NEXT_PUBLIC_SAFE_KEY" >>"$APP_DIR/.env"

# Install Nginx
sudo apt install nginx -y

# Remove old Nginx config (if it exists)
sudo rm -f /etc/nginx/sites-available/myapp
sudo rm -f /etc/nginx/sites-enabled/myapp

# Create Nginx config with reverse proxy, rate limiting, and streaming support
# Note: Nginx listens on HTTP only (port 80) - Cloudflare Tunnel handles SSL externally
sudo tee /etc/nginx/sites-available/myapp >/dev/null <<'EOL'
limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;

server {
    listen 80;
    server_name localhost;

    # Enable rate limiting
    limit_req zone=mylimit burst=20 nodelay;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;

        # Disable buffering for streaming support
        proxy_buffering off;
        proxy_set_header X-Accel-Buffering no;
    }
}
EOL

# Create symbolic link if it doesn't already exist
sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/myapp

# Restart Nginx to apply the new configuration
sudo systemctl restart nginx

# Install Cloudflare Tunnel (cloudflared)
# Check if cloudflared is already installed
if ! command -v cloudflared &>/dev/null; then
	echo "Installing Cloudflare Tunnel..."

	CLOUDFLARED_VERSION=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
	sudo wget -O /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/download/v${CLOUDFLARED_VERSION}/cloudflared-linux-${CLOUDFLARED_ARCH}"
	sudo chmod +x /usr/local/bin/cloudflared

	# Verify installation
	cloudflared --version
	if [ $? -ne 0 ]; then
		echo "Cloudflare Tunnel installation failed. Exiting."
		exit 1
	fi
else
	echo "Cloudflare Tunnel already installed."
fi

# Restart Docker to apply configuration
if sudo systemctl is-active --quiet docker; then
	sudo systemctl stop docker.socket 2>/dev/null
	sudo systemctl stop docker 2>/dev/null
	sleep 2
	sudo systemctl start docker
else
	sudo systemctl start docker
	sudo systemctl enable docker
fi
sleep 2

# Determine which docker-compose command to use (plugin or standalone)
if docker compose version &>/dev/null; then
	DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
	DOCKER_COMPOSE_CMD="docker-compose"
else
	echo "Docker Compose not found. Exiting."
	exit 1
fi

# Build and run the Docker containers from the app directory (~/myapp)
cd $APP_DIR
sudo $DOCKER_COMPOSE_CMD up --build -d

# Check if Docker Compose started correctly
if ! sudo $DOCKER_COMPOSE_CMD ps | grep -q "Up"; then
	echo "Docker containers failed to start. Check logs with '$DOCKER_COMPOSE_CMD logs'."
	exit 1
fi

# Output final message
echo "Deployment complete. Your Next.js app and PostgreSQL database are now running.
Nginx is configured as an internal reverse proxy on port 80.

NEXT STEPS - Configure Cloudflare Tunnel:
1. Authenticate with Cloudflare:
   cloudflared tunnel login

2. Create a tunnel:
   cloudflared tunnel create myapp

3. Configure the tunnel to route to localhost:80:
   cloudflared tunnel route dns myapp your-domain.com
   # Or use a config file at ~/.cloudflared/config.yml:
   # tunnel: <tunnel-id>
   # ingress:
   #   - hostname: your-domain.com
   #     service: http://localhost:80
   #   - service: http_status:404

4. Run the tunnel:
   cloudflared tunnel run myapp
   # Or set it up as a service for auto-start on boot

The .env file has been created with the following values:
- POSTGRES_USER
- POSTGRES_PASSWORD (randomly generated)
- POSTGRES_DB
- DATABASE_URL
- DATABASE_URL_EXTERNAL
- SECRET_KEY
- NEXT_PUBLIC_SAFE_KEY

Note: Nginx is listening on port 80 internally. Cloudflare Tunnel will handle
external SSL/TLS termination and route traffic to your Raspberry Pi."
