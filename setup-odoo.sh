#!/bin/bash
# Installation Odoo 18 avec image Tecnativa Doodba - VERSION OPTIMISEE

set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== DEBUT INSTALLATION ==="

# --------------------------------------
# 🔧 Installation des dépendances système
# --------------------------------------

echo "🔧 Mise à jour des paquets et installation des outils de base..."

apt-get update -y
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    git \
    python3 \
    python3-pip \
    software-properties-common \
    lsb-release

echo "🐳 Installation de Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

echo "📦 Installation de Docker Compose via pip..."
pip3 install docker-compose

echo "🔁 Redémarrage du service Docker..."
systemctl enable docker
systemctl start docker

echo "👤 Ajout de l'utilisateur 'ubuntu' au groupe docker..."
usermod -aG docker ubuntu

# --------------------------------------
# 📦 Variables Terraform / Paramètres Odoo
# --------------------------------------

echo "📦 Chargement des variables..."

PROJECT_NAME="${project_name:-demo-project}"
REGION_CODE="${region_code:-eu-west-3}"
REGION_CITY="${region_city:-paris}"
ENVIRONMENT="${environment:-dev}"
ODOO_VERSION="${odoo_version:-18.0}"  # Valeur par défaut
ADMIN_PASSWORD="${admin_password:-admin}"
DB_PASSWORD="${db_password:-odoo_db_pwd}"
MASTER_PASSWORD="${master_password:-odoo_master_pwd}"
ENABLE_DEMO="${enable_demo:-false}"
AUTO_CREATE_DB="${auto_create_db:-true}"
DEFAULT_DB_NAME="${default_db_name:-demo18}"
DEFAULT_LANGUAGE="${default_language:-fr_FR}"
DEFAULT_COUNTRY="${default_country:-FR}"
TIMEZONE="${timezone:-Europe/Paris}"
POSTGRES_VERSION="${postgres_version:-15}"
MAX_CONNECTIONS="${max_connections:-100}"
SHARED_BUFFERS="${shared_buffers:-128MB}"
WORK_MEM="${work_mem:-4MB}"
UBUNTU_VERSION="${ubuntu_version:-20.04}"

echo "✅ Variables chargées :"
echo "→ PROJECT_NAME = $PROJECT_NAME"
echo "→ ENVIRONMENT = $ENVIRONMENT"
echo "→ REGION = $REGION_CODE / $REGION_CITY"
echo "→ ODOO_VERSION = $ODOO_VERSION"
echo "→ DB_NAME = $DEFAULT_DB_NAME"
echo "→ LANGUE = $DEFAULT_LANGUAGE"
echo "→ PAYS = $DEFAULT_COUNTRY"
echo "→ TIMEZONE = $TIMEZONE"
echo "→ POSTGRES_VERSION = $POSTGRES_VERSION"

# --------------------------------------
# 🕒 Configuration du fuseau horaire
# --------------------------------------

echo "🕒 Configuration du fuseau horaire : $TIMEZONE"
timedatectl set-timezone "$TIMEZONE" || echo "⚠️ Échec de la configuration du fuseau horaire : $TIMEZONE"

echo "✅ Dépendances installées et fuseau horaire configuré."


log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${region_code}] - $1"
}

log "=== DEBUT INSTALLATION ${project_name} - ${region_city} (${region_code}) ==="
log "Odoo Version: 18.0 avec Doodba"
log "Ubuntu Version: ${ubuntu_version}"
log "Timezone: ${timezone}"

# Configuration timezone
log "Configuration timezone..."
timedatectl set-timezone "${timezone}"

# Mise a jour
log "Mise a jour Ubuntu..."
apt update -y && apt upgrade -y

# Docker
log "Installation Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Installation Docker Compose
log "Installation Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Utilitaires
log "Installation utilitaires..."
apt install -y nginx htop curl wget git jq tree python3-pip

# Structure
log "Creation structure..."
mkdir -p /opt/${project_name}/{configs,scripts,backups,logs,custom-addons,private}
chown -R ubuntu:ubuntu /opt/${project_name}

# Configuration Odoo avec Doodba
log "Configuration Odoo pour Doodba..."
cat > /opt/${project_name}/configs/odoo.conf << ODOOCONF
[options]
# Configuration Doodba optimisée
addons_path = /opt/odoo/custom/src/private,/opt/odoo/custom/src/repos,/opt/odoo/auto/addons,/opt/odoo/addons
data_dir = /opt/odoo/data
logfile = /var/log/odoo/odoo.log
log_level = info

# Authentification
admin_passwd = ${master_password}

# Base de données
db_host = db
db_port = 5432
db_user = odoo
db_password = ${db_password}
list_db = False
db_maxconn = ${max_connections}

# Réseau et proxy
proxy_mode = True
xmlrpc_interface = 0.0.0.0
xmlrpc_port = 8069

# Workers (0 = auto)
workers = 0
max_cron_threads = 2

# Configuration régionale
timezone = ${timezone}
default_language = ${default_language}

# Démo
without_demo = $([ "${enable_demo}" = "true" ] && echo "False" || echo "True")

# Sécurité
server_wide_modules = base,web
ODOOCONF

# Configuration repos.yaml pour Doodba
log "Configuration repos.yaml..."
cat > /opt/${project_name}/configs/repos.yaml << REPOSEOF
# Configuration des repositories pour Doodba
./odoo:
  defaults:
    depth: 1
  remotes:
    origin: https://github.com/odoo/odoo.git
  target:
    origin ${ODOO_VERSION}
  merges:
    - origin ${ODOO_VERSION}

# Ajoutez ici d'autres repos si nécessaire
# ./enterprise:
#   defaults:
#     depth: 1
#   remotes:
#     origin: https://github.com/odoo/enterprise.git
#   target:
#     origin ${ODOO_VERSION}
#   merges:
#     - origin ${ODOO_VERSION}
REPOSEOF

# Configuration addons.yaml pour Doodba
log "Configuration addons.yaml..."
cat > /opt/${project_name}/configs/addons.yaml << ADDONSEOF
# Configuration des addons pour Doodba
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

# Ajoutez ici vos addons personnalisés
# private:
#   - mon_addon_custom
ADDONSEOF

# Docker Compose avec Doodba
log "Configuration Docker Compose avec Doodba..."
cat > /opt/${project_name}/docker-compose.yml << DOCKEREOF
version: '3.8'

services:
  db:
    image: postgres:${postgres_version}-alpine
    container_name: ${project_name}-db-${region_code}
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: odoo
      POSTGRES_PASSWORD: ${db_password}
      PGDATA: /var/lib/postgresql/data/pgdata
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=en_US.UTF8"
    volumes:
      - db_data:/var/lib/postgresql/data/pgdata
      - ./backups:/backups
    command: |
      postgres
      -c max_connections=${max_connections}
      -c shared_buffers=${shared_buffers}
      -c work_mem=${work_mem}
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
    container_name: ${project_name}-app-${region_code}
    depends_on:
      db:
        condition: service_healthy
    environment:
      # Configuration base
      PGHOST: db
      PGUSER: odoo
      PGPASSWORD: ${db_password}
      PGDATABASE: postgres
      
      # Configuration Doodba
      ODOO_CONF: /opt/odoo/etc/odoo.conf
      REPOS_YAML: /opt/odoo/custom/src/repos.yaml
      ADDONS_YAML: /opt/odoo/custom/src/addons.yaml
      
      # Configuration système
      TZ: ${timezone}
      
      # Mode développement (optionnel)
      DOODBA_ENVIRONMENT: ${environment}
      
      # Configuration logging
      LOG_LEVEL: INFO
      
      # Configuration workers
      ODOO_WORKERS: 0
      
      # Configuration démo
      WITHOUT_DEMO: $([ "${enable_demo}" = "true" ] && echo "False" || echo "True")
    volumes:
      # Configuration
      - ./configs/odoo.conf:/opt/odoo/etc/odoo.conf:ro
      - ./configs/repos.yaml:/opt/odoo/custom/src/repos.yaml:ro
      - ./configs/addons.yaml:/opt/odoo/custom/src/addons.yaml:ro
      
      # Données et logs
      - odoo_data:/opt/odoo/data
      - ./logs:/var/log/odoo
      
      # Addons personnalisés
      - ./custom-addons:/opt/odoo/custom/src/private
      - ./private:/opt/odoo/custom/src/private-extra
      
      # Backups
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

# Configuration Nginx avec optimisations pour Doodba
log "Configuration Nginx..."
cat > /etc/nginx/sites-available/default << NGINXEOF
upstream odoo {
    server 127.0.0.1:8069;
}

server {
    listen 80 default_server;
    server_name _;
    
    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    
    # Headers de monitoring
    add_header X-Region "${region_code}" always;
    add_header X-City "${region_city}" always;
    add_header X-Environment "${environment}" always;
    add_header X-Project "${project_name}" always;
    add_header X-Odoo-Version "18.0-doodba" always;
    
    # Gzip compression
    gzip on;
    gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
    gzip_min_length 1000;
    
    # Configuration Odoo
    location / {
        proxy_pass http://odoo;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_redirect off;
        
        # Timeouts optimisés pour Doodba
        proxy_read_timeout 720s;
        proxy_connect_timeout 720s;
        proxy_send_timeout 720s;
        
        # Buffer sizes
        proxy_buffer_size 64k;
        proxy_buffers 8 64k;
        proxy_busy_buffers_size 64k;
        
        # WebSocket support pour longpolling
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Cache pour fichiers statiques
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://odoo;
        proxy_cache_valid 200 60m;
        add_header Cache-Control "public, max-age=3600";
        expires 1h;
    }
    
    # Endpoints de monitoring
    location /health {
        access_log off;
        return 200 "OK - ${project_name} - ${region_city} (${region_code}) - \$(date)";
        add_header Content-Type text/plain;
    }
    
    location /status {
        access_log off;
        return 200 "READY - ${project_name} - Odoo 18.0 Doodba - \$(date)";
        add_header Content-Type text/plain;
    }
    
    # Métriques Prometheus
    location /metrics {
        access_log off;
        return 200 "# HELP odoo_status Odoo application status\\n# TYPE odoo_status gauge\\nodoo_status{version=\\"18.0\\",image=\\"doodba\\",region=\\"${region_code}\\",city=\\"${region_city}\\"} 1\\n";
        add_header Content-Type text/plain;
    }
}
NGINXEOF

# Test et démarrage Nginx
log "Test et demarrage Nginx..."
nginx -t && systemctl restart nginx && systemctl enable nginx

# Service systemd
log "Creation service systemd..."
cat > /etc/systemd/system/${project_name}.service << SYSTEMDEOF
[Unit]
Description=${project_name} Odoo 18 Doodba
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/${project_name}
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
ExecReload=/usr/bin/docker-compose restart
TimeoutStartSec=900
TimeoutStopSec=300
User=root
Environment=COMPOSE_HTTP_TIMEOUT=600

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

systemctl daemon-reload
systemctl enable ${project_name}.service

# Scripts de gestion
log "Creation scripts de gestion..."

# Script de création de base adapté pour Doodba
cat > /opt/${project_name}/scripts/create-odoo-db.py << 'PYTHONEOF'
#!/usr/bin/env python3
import requests
import time
import sys
import os
import json

def wait_for_odoo(url, max_attempts=60):
    """Attendre que Odoo soit accessible"""
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
    """Créer une base de données Odoo"""
    
    # Données pour la création
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
            timeout=600,  # 10 minutes pour la création
            allow_redirects=True
        )
        
        if response.status_code == 200 and 'database_manager' not in response.url:
            print(f"✓ Base '{db_name}' créée avec succès!")
            return True
        else:
            print(f"✗ Erreur création: Status {response.status_code}")
            print(f"URL finale: {response.url}")
            return False
            
    except Exception as e:
        print(f"✗ Erreur création base: {e}")
        return False

def get_database_list(url):
    """Récupérer la liste des bases existantes"""
    try:
        response = requests.get(f"{url}/web/database/list", timeout=30)
        if response.status_code == 200:
            return response.json()
        return []
    except:
        return []

if __name__ == "__main__":
    # Configuration
    odoo_url = "http://localhost:8069"
    master_pwd = os.getenv('MASTER_PASSWORD', 'admin123')
    db_name = os.getenv('DEFAULT_DB_NAME', 'odoo18_db')
    admin_pwd = os.getenv('ADMIN_PASSWORD', 'admin')
    lang = os.getenv('DEFAULT_LANGUAGE', 'fr_FR')
    country = os.getenv('DEFAULT_COUNTRY', 'FR')
    demo = os.getenv('ENABLE_DEMO', 'false').lower() == 'true'
    
    print("=== CREATION BASE ODOO 18 DOODBA ===")
    print(f"URL: {odoo_url}")
    print(f"Base: {db_name}")
    print(f"Langue: {lang}")
    print(f"Pays: {country}")
    print(f"Démo: {'Oui' if demo else 'Non'}")
    print()
    
    # Attendre Odoo
    print("Attente de Odoo...")
    if not wait_for_odoo(odoo_url):
        print("✗ Impossible de contacter Odoo")
        sys.exit(1)
    
    # Vérifier si la base existe déjà
    print("Vérification des bases existantes...")
    existing_dbs = get_database_list(odoo_url)
    if db_name in existing_dbs:
        print(f"✓ Base '{db_name}' existe déjà")
    else:
        # Créer la base
        if create_database(odoo_url, master_pwd, db_name, admin_pwd, lang, country, demo):
            print("✓ Base créée avec succès!")
        else:
            print("✗ Échec création base")
            sys.exit(1)
    
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
    
    # Fichier texte lisible
    with open('/home/ubuntu/DATABASE_INFO.txt', 'w') as f:
        f.write("=== INFORMATIONS BASE ODOO 18 DOODBA ===\n")
        f.write(f"Base de données: {info['database']}\n")
        f.write(f"URL: {info['url']}\n")
        f.write(f"Utilisateur: {info['login']}\n")
        f.write(f"Mot de passe: {info['password']}\n")
        f.write(f"Master password: {info['master_password']}\n")
        f.write(f"Langue: {info['language']}\n")
        f.write(f"Pays: {info['country']}\n")
        f.write(f"Données démo: {'Oui' if info['demo_data'] else 'Non'}\n")
        f.write(f"Version: {info['version']}\n")
        f.write(f"Image: {info['image']}\n")
        f.write(f"Créé le: {info['created']}\n")
    
    # Fichier JSON pour l'automatisation
    with open('/home/ubuntu/database_info.json', 'w') as f:
        json.dump(info, f, indent=2)
    
    print("✓ Informations sauvées dans /home/ubuntu/DATABASE_INFO.txt")
    print("✓ Configuration JSON dans /home/ubuntu/database_info.json")
PYTHONEOF

# Script de backup optimisé pour Doodba
cat > /opt/${project_name}/scripts/backup.sh << 'BACKUPEOF'
#!/bin/bash
BACKUP_DIR="/opt/${project_name}/backups"
DATE=$(date +%Y%m%d_%H%M%S)
PROJECT_NAME="${project_name}"
REGION_CODE="${region_code}"
DEFAULT_DB_NAME="${default_db_name}"

echo "=== BACKUP ODOO 18 DOODBA - $DATE ==="

# Créer le répertoire de backup
mkdir -p $BACKUP_DIR

# Backup PostgreSQL complet
echo "Backup PostgreSQL complet..."
docker exec ${PROJECT_NAME}-db-${REGION_CODE} pg_dumpall -U odoo > $BACKUP_DIR/postgres_full_$DATE.sql
gzip $BACKUP_DIR/postgres_full_$DATE.sql

# Backup base spécifique si elle existe
if docker exec ${PROJECT_NAME}-db-${REGION_CODE} psql -U odoo -lqt | cut -d \| -f 1 | grep -qw ${DEFAULT_DB_NAME}; then
    echo "Backup base ${DEFAULT_DB_NAME}..."
    docker exec ${PROJECT_NAME}-db-${REGION_CODE} pg_dump -U odoo -d ${DEFAULT_DB_NAME} > $BACKUP_DIR/${DEFAULT_DB_NAME}_$DATE.sql
    gzip $BACKUP_DIR/${DEFAULT_DB_NAME}_$DATE.sql
fi

# Backup volumes Docker
echo "Backup volumes Docker..."
docker run --rm -v ${PROJECT_NAME}_db_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/db_volume_$DATE.tar.gz -C /data .
docker run --rm -v ${PROJECT_NAME}_odoo_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/odoo_volume_$DATE.tar.gz -C /data .

# Backup configuration et addons
echo "Backup configuration..."
tar czf $BACKUP_DIR/config_$DATE.tar.gz -C /opt/${PROJECT_NAME} configs/ custom-addons/ private/

# Backup avec informations sur l'image
echo "Création metadata backup..."
cat > $BACKUP_DIR/backup_info_$DATE.json << INFOEOF
{
  "date": "$DATE",
  "project": "${PROJECT_NAME}",
  "region": "${REGION_CODE}",
  "odoo_version": "18.0",
  "image": "tecnativa/doodba",
  "database": "${DEFAULT_DB_NAME}",
  "backup_type": "full"
}
INFOEOF

# Nettoyer anciens backups (garder 7 jours)
echo "Nettoyage anciens backups..."
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
find $BACKUP_DIR -name "*.json" -mtime +7 -delete

# Statistiques
echo "=== BACKUP TERMINE ==="
echo "Date: $DATE"
echo "Taille totale: $(du -sh $BACKUP_DIR | cut -f1)"
echo "Fichiers créés:"
ls -lah $BACKUP_DIR/*$DATE*
BACKUPEOF

# Script de monitoring avancé
cat > /opt/${project_name}/scripts/monitor.sh << 'MONITOREOF'
#!/bin/bash

PROJECT_NAME="${project_name}"
REGION_CODE="${region_code}"
REGION_CITY="${region_city}"

echo "=== MONITORING ${PROJECT_NAME} - ODOO 18 DOODBA ==="
echo "Date: $(date)"
echo "Région: ${REGION_CITY} (${REGION_CODE})"
echo ""

echo "=== STATUS SYSTEME ==="
echo "Timezone: $(timedatectl | grep 'Time zone')"
echo "Load: $(uptime | cut -d',' -f3- | cut -d':' -f2)"
echo "Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')"
echo "Disk: $(df -h /opt/${PROJECT_NAME} | tail -1 | awk '{print $3"/"$2" ("$5")"}')"
echo ""

echo "=== SERVICES SYSTEME ==="
for service in docker nginx ${PROJECT_NAME}; do
    status=$(systemctl is-active $service)
    echo "$service: $status"
done
echo ""

echo "=== CONTAINERS DOCKER ==="
cd /opt/${PROJECT_NAME}
docker-compose ps
echo ""

echo "=== HEALTH CHECKS ==="
echo -n "Nginx: "
curl -s -w "%{http_code}" http://localhost/health -o /dev/null
echo ""

echo -n "Odoo: "
curl -s -w "%{http_code}" http://localhost:8069/web/health -o /dev/null 2>/dev/null || echo "N/A"
echo ""

echo "=== INFORMATIONS ODOO ==="
if docker ps | grep -q ${PROJECT_NAME}-app-${REGION_CODE}; then
    echo "Container Odoo: ✓ Running"
    echo "Version: 18.0 (Doodba)"
    echo "Image: $(docker inspect ${PROJECT_NAME}-app-${REGION_CODE} | jq -r '.[0].Config.Image')"
    echo "Uptime: $(docker inspect ${PROJECT_NAME}-app-${REGION_CODE} | jq -r '.[0].State.StartedAt')"
else
    echo "Container Odoo: ✗ Stopped"
fi
echo ""

echo "=== BASE DE DONNEES ==="
if docker ps | grep -q ${PROJECT_NAME}-db-${REGION_CODE}; then
    echo "Container PostgreSQL: ✓ Running"
    echo "Bases disponibles:"
    docker exec ${PROJECT_NAME}-db-${REGION_CODE} psql -U odoo -l 2>/dev/null | grep -E '^\s+\w+' | head -10
else
    echo "Container PostgreSQL: ✗ Stopped"
fi
echo ""

echo "=== LOGS RECENTS ==="
echo "Derniers logs Odoo:"
docker logs ${PROJECT_NAME}-app-${REGION_CODE} --tail=5 2>/dev/null || echo "Logs non disponibles"
echo ""

echo "=== CONNEXIONS ==="
echo "Ports ouverts:"
netstat -tlnp | grep -E ':(80|8069|5432)' | head -5
echo ""

echo "=== RESSOURCES ==="
if command -v docker stats >/dev/null; then
    echo "Stats containers (snapshot):"
    timeout 3 docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -5
fi
MONITOREOF

# Script de mise à jour Doodba
cat > /opt/${project_name}/scripts/update-doodba.sh << 'UPDATEEOF'
#!/bin/bash
PROJECT_NAME="${project_name}"
REGION_CODE="${region_code}"

echo "=== MISE A JOUR DOODBA ==="

cd /opt/${PROJECT_NAME}

# Sauvegarder avant mise à jour
echo "Backup avant mise à jour..."
./scripts/backup.sh

# Arrêter les services
echo "Arrêt des services..."
docker-compose down

# Mettre à jour l'image
echo "Mise à jour image Doodba..."
docker-compose pull

# Redémarrer
echo "Redémarrage..."
docker-compose up -d

# Vérifier
sleep 30
echo "Vérification après mise à jour..."
./scripts/monitor.sh

echo "=== MISE A JOUR TERMINEE ==="
UPDATEEOF

# Rendre les scripts exécutables
chmod +x /opt/${project_name}/scripts/*.sh
chmod +x /opt/${project_name}/scripts/*.py
chown -R ubuntu:ubuntu /opt/${project_name}

# Installation packages Python
log "Installation packages Python..."
pip3 install requests

# Démarrage initial
log "Demarrage initial Doodba..."
cd /opt/${project_name}

# Pull de l'image Doodba
log "Pull image Doodba 18.0..."
docker-compose pull

# Démarrage
log "Demarrage services..."
docker-compose up -d --remove-orphans

# Vérifications immédiates
log "Verifications immediates..."
sleep 10
docker-compose ps
docker-compose logs --tail=20

# Démarrage service systemd
systemctl start ${project_name}.service

# Attendre que les services soient prêts
log "Attente services (peut prendre quelques minutes avec Doodba)..."
for i in {1..60}; do
    if systemctl is-active --quiet ${project_name}.service; then
        log "Service systemd actif"
        break
    fi
    log "Attente service... ($i/60)"
    sleep 30
done

# Attendre Odoo spécifiquement
log "Attente Odoo Doodba (initialisation complète)..."
for i in {1..90}; do
    if curl -f -s http://localhost:8069/web/database/selector > /dev/null 2>&1; then
        log "✓ Odoo Doodba operationnel!"
        break
    fi
    log "Attente Odoo... ($i/90)"
    sleep 20
done

# Test final
log "Test final connectivité..."
curl -I http://localhost:8069/ || log "ATTENTION: Odoo non accessible"

# Création base automatique si demandée
if [ "${auto_create_db}" = "true" ]; then
    log "Creation automatique base Odoo..."
    cd /opt/${project_name}/scripts
    
    # Export des variables pour le script Python
    export MASTER_PASSWORD="${master_password}"
    export DEFAULT_DB_NAME="${default_db_name}"
    export ADMIN_PASSWORD="${admin_password}"
    export DEFAULT_LANGUAGE="${default_language}"
    export DEFAULT_COUNTRY="${default_country}"
    export ENABLE_DEMO="${enable_demo}"
    
    python3 create-odoo-db.py
    
    if [ $? -eq 0 ]; then
        log "✓ Base Odoo creee avec succes"
    else
        log "✗ ERREUR: Echec creation base"
    fi
fi

# Configuration cron backups
log "Configuration sauvegardes automatiques..."
cat > /etc/cron.d/${project_name}-backup << CRONEOF
# Backup automatique Odoo 18 Doodba
0 2 * * * root /opt/${project_name}/scripts/backup.sh >> /var/log/backup-${project_name}.log 2>&1
# Monitoring quotidien
0 8 * * * root /opt/${project_name}/scripts/monitor.sh >> /var/log/monitor-${project_name}.log 2>&1
CRONEOF

chmod 644 /etc/cron.d/${project_name}-backup
