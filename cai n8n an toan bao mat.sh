#!/bin/bash

#------------------------------------------------------------------
# COMPLETE AUTOMATED INSTALLATION SCRIPT
# Author: Ticmiro
# Functionality:
# - Installs n8n with PostgreSQL on a fresh VPS.
# - Automates Docker installation, Reverse Proxy, and HTTPS with Caddy.
# - Uses a stable n8n version and configures Vietnam timezone.
#------------------------------------------------------------------

# --- Utilities ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Stop immediately if any command fails
set -e

echo -e "${GREEN}Welcome to the complete automated installation script for n8n!${NC}"
echo -e "${GREEN}Author: Ticmiro & Gemini${NC}"
echo "------------------------------------------------------------------"

# --- STEP 1: PROMPT USER FOR INFORMATION ---
echo -e "${YELLOW}Please provide the necessary configuration details:${NC}"

read -p "Enter the domain you will use for n8n (e.g., n8n.yourdomain.com): " DOMAIN_NAME
read -p "Enter your email address (for SSL renewal notifications): " EMAIL_ADDRESS
read -p "Enter a name for the PostgreSQL User (e.g., n8n_user): " POSTGRES_USER
read -s -p "Enter a password for the PostgreSQL User: " POSTGRES_PASSWORD
echo
read -p "Enter a name for the PostgreSQL Database (e.g., n8n_db): " POSTGRES_DB

if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL_ADDRESS" ] || [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
  echo -e "${RED}Error: All information fields must be filled out.${NC}"
  exit 1
fi

echo ""
echo "--- Configuration will be set up for domain: $DOMAIN_NAME ---"
echo ""

# --- STEP 2: INSTALL NECESSARY SYSTEM PACKAGES ---
echo -e "${YELLOW}--> Updating system and installing basic packages...${NC}"
sudo apt-get update
sudo apt-get install -y ca-certificates curl git

# --- STEP 3: CHECK FOR AND INSTALL DOCKER ---
if ! command -v docker &> /dev/null
then
    echo -e "${YELLOW}--> Docker is not installed. Starting Docker installation...${NC}"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo -e "${GREEN}--> Docker installation complete.${NC}"
else
    echo -e "${GREEN}--> Docker is already installed. Skipping this step.${NC}"
fi

# --- STEP 4: CONFIGURE DOCKER AND FIREWALL ---
echo -e "${YELLOW}--> Configuring Docker to prefer IPv4...${NC}"
sudo cat > /etc/docker/daemon.json << EOF
{
  "ipv6": false
}
EOF
sudo systemctl restart docker

echo -e "${YELLOW}--> Configuring UFW firewall...${NC}"
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# --- STEP 5: CREATE CONFIGURATION FILES AND DEPLOY DOCKER ---
INSTALL_DIR="$HOME/n8n-caddy-stack"
echo -e "${YELLOW}--> Creating configuration files at ${INSTALL_DIR}...${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create the .env file
cat > .env << EOF
# PostgreSQL login details
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

# Timezone for n8n
TZ=Asia/Ho_Chi_Minh
EOF

# Create the Caddyfile
cat > Caddyfile << EOF
${DOMAIN_NAME} {
    reverse_proxy n8n:5678
}
EOF

# Create the docker-compose.yml file
cat > docker-compose.yml << EOF
version: '3.7'

services:
  caddy:
    image: caddy:latest
    container_name: caddy_reverse_proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - n8n_network

  postgres:
    image: postgres:15
    container_name: n8n_postgres_db
    restart: always
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n_network

  n8n:
    # Use a stable n8n version
    image: n8nio/n8n:1.45.1
    container_name: n8n_service
    restart: always
    user: "root" # Run with root privileges to avoid permission denied errors
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - N8N_HOST=${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_NAME}/
      - TZ=\${TZ}
      # Thêm các biến môi trường để khắc phục cảnh báo
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_RUNNERS_ENABLED=true
    volumes:
      - ./n8n-data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - n8n_network

networks:
  n8n_network:
    driver: bridge

volumes:
  caddy_data: {}
  caddy_config: {}
  postgres-data: {}
  n8n-data: {}
EOF

echo -e "${YELLOW}--> Starting services (Caddy, n8n, PostgreSQL)...${NC}"
sudo docker compose up -d

# --- STEP 6: FINALIZATION ---
echo "=================================================================="
echo -e "${GREEN}🚀 INSTALLATION COMPLETE! 🚀${NC}"
echo "=================================================================="
echo ""
echo "Caddy will automatically obtain and configure the SSL certificate for you within a few minutes."
echo "You can access n8n now at: ${GREEN}https://${DOMAIN_NAME}${NC}"
echo "Your database credentials have been saved in the file: ${GREEN}${INSTALL_DIR}/.env${NC}"
echo ""
echo "To view the system logs, run: ${YELLOW}cd ${INSTALL_DIR} && sudo docker compose logs -f${NC}"
echo "=================================================================="