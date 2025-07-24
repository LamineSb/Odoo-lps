#!/bin/bash
# Installation Odoo 18 avec image Tecnativa Doodba - VERSION CORRIGEE UBUNTU 20.04

set -e

echo "=== DEBUT INSTALLATION ==="

# Variables Terraform (conservées identiques)
PROJECT_NAME="${project_name}"
REGION_CODE="${region_code}"
REGION_CITY="${region_city}"
ENVIRONMENT="${environment}"
ODOO_VERSION="18.0"
ADMIN_PASSWORD="${admin_password}"
DB_PASSWORD="${db_password}"
MASTER_PASSWORD="${master_password}"
ENABLE_DEMO="${enable_demo}"
AUTO_CREATE_DB="${auto_create_db}"
DEFAULT_DB_NAME="${default_db_name}"
DEFAULT_LANGUAGE="${default_language}"
DEFAULT_COUNTRY="${default_country}"
TIMEZONE="${timezone}"
POSTGRES_VERSION="${postgres_version}"
MAX_CONNECTIONS="${max_connections}"
SHARED_BUFFERS="${shared_buffers}"
WORK_MEM="${work_mem}"
UBUNTU_VERSION="${ubuntu_version}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${REGION_CODE}] - $1"
}

log "=== DEBUT INSTALLATION ${PROJECT_NAME} - ${REGION_CITY} (${REGION_CODE}) ==="
log "Odoo Version: 18.0 avec Doodba"
log "Ubuntu Version: ${UBUNTU_VERSION}"
log "Timezone: ${TIMEZONE}"

# Configuration timezone
log "Configuration timezone..."
timedatectl set-timezone "${TIMEZONE}"

# Mise à jour
log "Mise à jour Ubuntu..."
apt update -y && apt upgrade -y

# Docker
log "Installation Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Installation Docker Compose - METHODE CORRIGEE
log "Installation Docker Compose..."
COMPOSE_VERSION="v2.30.3"
log "Installation Docker Compose $COMPOSE_VERSION..."

curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Test et fallback
if docker-compose --version 2>/dev/null; then
    log "✓ Docker Compose installé avec succès"
else
    log "Tentative installation via apt..."
    apt update
    apt install -y docker-compose
fi

# Vérification finale
docker-compose --version || {
    log "ERREUR: Docker Compose non installé"
    exit 1
}

# Utilitaires
log "Installation utilitaires..."
apt install -y nginx htop curl wget git jq tree

# Python - INSTALLATION VIA APT UNIQUEMENT
log "Installation Python packages..."
apt install -y python3-requests python3-setuptools

# Test Python
python3 -c "import requests; print('✓ Python requests OK')" || {
    log "ERREUR: Python requests non disponible"
    exit 1
}

# Structure (identique)
log "Creation structure..."
mkdir -p /opt/${PROJECT_NAME}/{configs,scripts,backups,logs,custom-addons,private}
chown -R ubuntu:ubuntu /opt/${PROJECT_NAME}

# Configuration Odoo avec Doodba (identique)
log "Configuration Odoo pour Doodba..."
cat > /opt/${PROJECT_NAME}/configs/odoo.conf << ODOOCONF
[options]
addons_path = /opt/odoo/custom/src/private,/opt/odoo/custom/src/repos,/opt/odoo/auto/addons,/opt/odoo/addons
data_dir = /opt/odoo/data
logfile = /var/log/odoo/odoo.log
log_level = info

admin_passwd = ${MASTER_PASSWORD}

db_host = db
db_port = 5432
db_user = odoo
db_password = ${DB_PASSWORD}
list_db = False
db_maxconn = ${MAX_CONNECTIONS}

proxy_mode = True
xmlrpc_interface = 0.0.0.0
xmlrpc_port = 8069

workers = 0
max_cron_threads = 2

timezone = ${TIMEZONE}
default_language = ${DEFAULT_LANGUAGE}

without_demo = $([ "${ENABLE_DEMO}" = "true" ] && echo "False" || echo "True")

server_wide_modules = base,web
ODOOCONF

# Configuration repos.yaml pour Doodba (identique)
log "Configuration repos.yaml..."
cat > /opt/${PROJECT_NAME}/configs/repos.yaml << REPOSEOF
./odoo:
  defaults:
    depth: 1
  remotes:
    origin: https://github.com/odoo/odoo.git
  target:
    origin ${ODOO_VERSION}
  merges:
    - origin ${ODOO_VERSION}
REPOSEOF

# Configuration addons.yaml pour Doodba (identique)
log "Configuration addons.yaml..."
cat > /opt/${PROJECT_NAME}/configs/addons.yaml << ADDONSEOF
server_wide:
  - base
  - web

odoo:
  - account
  - sale
  - purchase
  - stock
  - crm
  - project
  - hr
  - website
  - mail
  - calendar
ADDONSEOF

# Docker Compose avec Doodba (identique à votre version)
log "Configuration Docker Compose avec Doodba..."
cat > /opt/${PROJECT_NAME}/docker-compose.yml << DOCKEREOF
version: '3.8'

services:
  db:
    image: postgres:${POSTGRES_VERSION:-15}-alpine
    container_name: ${PROJECT_NAME}-db-${REGION_CODE}
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=en_US.UTF8"
    volumes:
      - db_data:/var/lib/postgresql/data/pgdata
      - ./backups:/backups
    command: |
      postgres
      -c max_connections=${MAX_CONNECTIONS:-100}
      -c shared_buffers=${SHARED_BUFFERS:-128MB}
      -c work_mem=${WORK_MEM:-4MB}
      -c maintenance_work_mem=64MB
      -c effective_cache_size=512MB
      -c wal_buffers=16MB
      -c checkpoint_completion_target=0.9
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - odoo_network

  odoo:
    image: tecnativa/doodba:18.0-latest
    container_name: ${PROJECT_NAME}-app-${REGION_CODE}
    depends_on:
      db:
        condition: service_healthy
    environment:
      PGHOST: db
      PGUSER: odoo
      PGPASSWORD: ${DB_PASSWORD}
      PGDATABASE: postgres
      
      ODOO_CONF: /opt/odoo/etc/odoo.conf
      REPOS_YAML: /opt/odoo/custom/src/repos.yaml
      ADDONS_YAML: /opt/odoo/custom/src/addons.yaml
      
      TZ: ${TIMEZONE}
      DOODBA_ENVIRONMENT: ${ENVIRONMENT}
      LOG_LEVEL: INFO
      ODOO_WORKERS: 0
      
      WITHOUT_DEMO: $([ "${ENABLE_DEMO}" = "true" ] && echo "False" || echo "True")
    volumes:
      - ./configs/odoo.conf:/opt/odoo/etc/odoo.conf:ro
      - ./configs/repos.yaml:/opt/odoo/custom/src/repos.yaml:ro
      - ./configs/addons.yaml:/opt/odoo/custom/src/addons.yaml:ro
      
      - odoo_data:/opt/odoo/data
      - ./logs:/var/log/odoo
      - ./custom-addons:/opt/odoo/custom/src/private
      - ./private:/opt/odoo/custom/src/private-extra
      - ./backups:/opt/odoo/backups
    ports:
      - "8069:8069"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s
    networks:
      - odoo_network

volumes:
  db_data:
  odoo_data:

networks:
  odoo_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
DOCKEREOF

# Configuration Nginx (identique)
log "Configuration Nginx..."
cat > /etc/nginx/sites-available/default << NGINXEOF
upstream odoo {
    server 127.0.0.1:8069;
}

server {
    listen 80 default_server;
    server_name _;
    
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    
    add_header X-Region "${REGION_CODE}" always;
    add_header X-City "${REGION_CITY}" always;
    add_header X-Environment "${ENVIRONMENT}" always;
    add_header X-Project "${PROJECT_NAME}" always;
    add_header X-Odoo-Version "18.0-doodba" always;
    
    gzip on;
    gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
    gzip_min_length 1000;
    
    location / {
        proxy_pass http://odoo;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        
        proxy_read_timeout 720s;
        proxy_connect_timeout 720s;
        proxy_send_timeout 720s;
        
        proxy_buffer_size 64k;
        proxy_buffers 8 64k;
        proxy_busy_buffers_size 64k;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://odoo;
        proxy_cache_valid 200 60m;
        add_header Cache-Control "public, max-age=3600";
        expires 1h;
    }
    
    location /health {
        access_log off;
        return 200 "OK - ${PROJECT_NAME} - ${REGION_CITY} (${REGION_CODE})";
        add_header Content-Type text/plain;
    }
}
NGINXEOF

# Test et démarrage Nginx
log "Test et demarrage Nginx..."
nginx -t && systemctl restart nginx && systemctl enable nginx

# Service systemd (identique)
log "Creation service systemd..."
cat > /etc/systemd/system/${PROJECT_NAME}.service << SYSTEMDEOF
[Unit]
Description=${PROJECT_NAME} Odoo 18 Doodba
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/${PROJECT_NAME}
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart
TimeoutStartSec=900
TimeoutStopSec=300
User=root
Environment=COMPOSE_HTTP_TIMEOUT=600

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

systemctl daemon-reload
systemctl enable ${PROJECT_NAME}.service

# Scripts de gestion - VERSION SANS PIP
log "Creation scripts de gestion..."

# Script de création de base - VERSION CORRIGEE
cat > /opt/${PROJECT_NAME}/scripts/create-odoo-db.py << 'PYTHONEOF'
#!/usr/bin/env python3
# Script creation base Odoo - Version sans pip
import requests
import time
import sys
import os
import json

def wait_for_odoo(url, max_attempts=60):
    for i in range(max_attempts):
        try:
            response = requests.get(f"{url}/web/database/selector", timeout=30)
            if response.status_code == 200:
                print(f"✓ Odoo accessible après {i+1} tentatives")
                return True
        except Exception as e:
            print(f"Tentative {i+1}/{max_attempts}: {e}")
        time.sleep(15)
    return False

def create_database(url, master_pwd, db_name, admin_pwd, lang, country, demo):
    data = {
        'master_pwd': master_pwd,
        'name': db_name,
        'login': 'admin',
        'password': admin_pwd,
        'phone': '',
        'lang': lang,
        'country_code': country,
    }
    
    if demo:
        data['demo'] = 'on'
    
    try:
        print(f"Création de la base '{db_name}'...")
        response = requests.post(
            f"{url}/web/database/create",
            data=data,
            timeout=600,
            allow_redirects=True
        )
        
        if response.status_code == 200 and 'database_manager' not in response.url:
            print(f"✓ Base '{db_name}' créée avec succès!")
            return True
        else:
            print(f"✗ Erreur création: Status {response.status_code}")
            return False
            
    except Exception as e:
        print(f"✗ Erreur création base: {e}")
        return False

if __name__ == "__main__":
    odoo_url = "http://localhost:8069"
    master_pwd = os.getenv('MASTER_PASSWORD', 'admin123')
    db_name = os.getenv('DEFAULT_DB_NAME', 'odoo18_db')
    admin_pwd = os.getenv('ADMIN_PASSWORD', 'admin')
    lang = os.getenv('DEFAULT_LANGUAGE', 'fr_FR')
    country = os.getenv('DEFAULT_COUNTRY', 'FR')
    demo = os.getenv('ENABLE_DEMO', 'false').lower() == 'true'
    
    print("=== CREATION BASE ODOO 18 DOODBA ===")
    print(f"Base: {db_name}")
    print(f"Langue: {lang}")
    print(f"Pays: {country}")
    print()
    
    if not wait_for_odoo(odoo_url):
        print("✗ Impossible de contacter Odoo")
        sys.exit(1)
    
    if create_database(odoo_url, master_pwd, db_name, admin_pwd, lang, country, demo):
        print("✓ Base créée avec succès!")
        
        # Sauvegarder les informations
        info = {
            'database': db_name,
            'url': odoo_url,
            'login': 'admin',
            'password': admin_pwd,
            'master_password': master_pwd,
            'language': lang,
            'country': country,
            'demo_data': demo,
            'version': '18.0',
            'image': 'tecnativa/doodba',
            'created': time.strftime('%Y-%m-%d %H:%M:%S')
        }
        
        with open('/home/ubuntu/DATABASE_INFO.txt', 'w') as f:
            f.write("=== BASE ODOO 18 DOODBA ===\n")
            f.write(f"URL: {info['url']}\n")
            f.write(f"Base: {info['database']}\n")
            f.write(f"Login: {info['login']}\n")
            f.write(f"Password: {info['password']}\n")
            f.write(f"Master: {info['master_password']}\n")
            f.write(f"Langue: {info['language']}\n")
            f.write(f"Créé: {info['created']}\n")
        
        print("✓ Infos sauvées dans /home/ubuntu/DATABASE_INFO.txt")
    else:
        print("✗ Échec création base")
        sys.exit(1)
PYTHONEOF

chmod +x /opt/${PROJECT_NAME}/scripts/create-odoo-db.py
chown -R ubuntu:ubuntu /opt/${PROJECT_NAME}

# Démarrage initial
log "Demarrage initial Doodba..."
cd /opt/${PROJECT_NAME}

log "Pull image Doodba 18.0..."
docker-compose pull

log "Demarrage services..."
docker-compose up -d --remove-orphans

sleep 10
docker-compose ps
docker-compose logs --tail=20

systemctl start ${PROJECT_NAME}.service

# Attendre services
log "Attente services..."
for i in {1..60}; do
    if systemctl is-active --quiet ${PROJECT_NAME}.service; then
        log "Service systemd actif"
        break
    fi
    log "Attente service... ($i/60)"
    sleep 30
done

# Attendre Odoo
log "Attente Odoo Doodba..."
for i in {1..90}; do
    if curl -f -s http://localhost:8069/web/database/selector > /dev/null 2>&1; then
        log "✓ Odoo Doodba operationnel!"
        break
    fi
    log "Attente Odoo... ($i/90)"
    sleep 20
done

# Test final
log "Test final..."
curl -I http://localhost:8069/ || log "ATTENTION: Odoo non accessible"

# Création base automatique
if [ "${AUTO_CREATE_DB}" = "true" ]; then
    log "Creation automatique base..."
    cd /opt/${PROJECT_NAME}/scripts
    
    export MASTER_PASSWORD="${MASTER_PASSWORD}"
    export DEFAULT_DB_NAME="${DEFAULT_DB_NAME}"
    export ADMIN_PASSWORD="${ADMIN_PASSWORD}"
    export DEFAULT_LANGUAGE="${DEFAULT_LANGUAGE}"
    export DEFAULT_COUNTRY="${DEFAULT_COUNTRY}"
    export ENABLE_DEMO="${ENABLE_DEMO}"
    
    python3 create-odoo-db.py
fi

log "=== INSTALLATION TERMINEE ==="
