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

# Add Swap Space
echo "Adding swap space..."
sudo fallocate -l $SWAP_SIZE /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Install Docker

sudo apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=$DOCKER_ARCH] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y
sudo apt update
sudo apt install docker-ce -y

# Install Docker Compose
sudo rm -f /usr/local/bin/docker-compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Wait for the file to be fully downloaded before proceeding
if [ ! -f /usr/local/bin/docker-compose ]; then
	echo "Docker Compose download failed. Exiting."
	exit 1
fi

sudo chmod +x /usr/local/bin/docker-compose

# Ensure Docker Compose is executable and in path
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose --version
if [ $? -ne 0 ]; then
	echo "Docker Compose installation failed. Exiting."
	exit 1
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
sudo cat >/etc/nginx/sites-available/myapp <<EOL
limit_req_zone \$binary_remote_addr zone=mylimit:10m rate=10r/s;

server {
    listen 80;
    server_name localhost;

    # Enable rate limiting
    limit_req zone=mylimit burst=20 nodelay;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;

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

# Build and run the Docker containers from the app directory (~/myapp)
cd $APP_DIR
sudo docker-compose up --build -d

# Check if Docker Compose started correctly
if ! sudo docker-compose ps | grep "Up"; then
	echo "Docker containers failed to start. Check logs with 'docker-compose logs'."
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
