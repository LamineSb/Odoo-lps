#!/bin/bash
# Installation Odoo evolutive avec base automatique - VERSION CORRIGEE

set -e
exec > >(tee /var/log/user-data.log) 2>&1

# Variables Terraform - CORRECTION: utilisation correcte des variables
PROJECT_NAME="${project_name}"
REGION_CODE="${region_code}"
REGION_CITY="${region_city}"
ENVIRONMENT="${environment}"
ODOO_VERSION="${odoo_version}"
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${region_code}] - $1"
}

log "=== DEBUT INSTALLATION ${project_name} - ${region_city} (${region_code}) ==="
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

# Installation Docker Compose - CORRECTION: installation explicite
log "Installation Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Utilitaires
log "Installation utilitaires..."
apt install -y nginx htop curl wget git jq tree python3-pip

# Structure
log "Creation structure..."
mkdir -p /opt/${project_name}/{configs,scripts,backups,logs,custom-addons}
chown -R ubuntu:ubuntu /opt/${project_name}

# Configuration Odoo avancée
log "Configuration Odoo..."
cat > /opt/${project_name}/configs/odoo.conf << ODOOCONF
[options]
addons_path = /mnt/extra-addons,/usr/lib/python3/dist-packages/odoo/addons
data_dir = /var/lib/odoo
logfile = /var/log/odoo/odoo.log
log_level = info
admin_passwd = ${master_password}
db_host = db
db_port = 5432
db_user = odoo
db_password = ${db_password}
list_db = False
proxy_mode = True
workers = 0
without_demo = $([ "${enable_demo}" = "true" ] && echo "False" || echo "True")

# Configuration régionale
timezone = ${timezone}
default_language = ${default_language}

# Configuration base de données
db_maxconn = ${max_connections}
ODOOCONF

# Docker Compose avec configuration optimisée - CORRECTION: substitution de variables
log "Configuration Docker Compose optimisee..."
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
      # Configuration PostgreSQL optimisée
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=en_US.UTF8"
    volumes:
      - db_data:/var/lib/postgresql/data/pgdata
      - ./backups:/backups
      - ./configs/postgresql.conf:/etc/postgresql/postgresql.conf:ro
    command: |
      postgres
      -c max_connections=${max_connections}
      -c shared_buffers=${shared_buffers}
      -c work_mem=${work_mem}
      -c maintenance_work_mem=64MB
      -c effective_cache_size=256MB
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - odoo_network

  odoo:
    image: odoo:${odoo_version}
    container_name: ${project_name}-app-${region_code}
    depends_on:
      db:
        condition: service_healthy
    environment:
      HOST: db
      USER: odoo
      PASSWORD: ${db_password}
      PGDATABASE: postgres
      # Configuration Odoo
      TZ: ${timezone}
    volumes:
      - odoo_data:/var/lib/odoo
      - ./custom-addons:/mnt/extra-addons
      - ./configs/odoo.conf:/etc/odoo/odoo.conf:ro
      - ./logs:/var/log/odoo
    ports:
      - "8069:8069"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - odoo_network

volumes:
  db_data:
  odoo_data:

networks:
  odoo_network:
    driver: bridge
DOCKEREOF

# Configuration PostgreSQL optimisée
log "Configuration PostgreSQL..."
cat > /opt/${project_name}/configs/postgresql.conf << PGCONF
# Configuration PostgreSQL pour Odoo
max_connections = ${max_connections}
shared_buffers = ${shared_buffers}
work_mem = ${work_mem}
maintenance_work_mem = 64MB
effective_cache_size = 256MB
wal_buffers = 16MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1
effective_io_concurrency = 200
PGCONF

# Configuration Nginx avec monitoring avancé - CORRECTION: substitution de variables
log "Configuration Nginx..."
cat > /etc/nginx/sites-available/default << NGINXEOF
server {
    listen 80 default_server;
    server_name _;
    
    # Headers de monitoring
    add_header X-Region "${region_code}" always;
    add_header X-City "${region_city}" always;
    add_header X-Environment "${environment}" always;
    add_header X-Project "${project_name}" always;
    add_header X-Ubuntu-Version "${ubuntu_version}" always;
    
    # Configuration Odoo
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        
        # Configuration pour Odoo longpolling
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Endpoints de monitoring
    location /health {
        access_log off;
        return 200 "OK - ${project_name} - ${region_city} (${region_code}) - \$(date)";
        add_header Content-Type text/plain;
    }
    
    location /status {
        access_log off;
        return 200 "READY - ${project_name} - ${region_city} (${region_code}) - Ubuntu: ${ubuntu_version}";
        add_header Content-Type text/plain;
    }
    
    location /info {
        access_log off;
        return 200 "Instance Info Available";
        add_header Content-Type text/plain;
    }
    
    # Métriques pour monitoring
    location /metrics {
        access_log off;
        return 200 "# HELP odoo_status Odoo application status\\n# TYPE odoo_status gauge\\nodoo_status{region=\\"${region_code}\\",city=\\"${region_city}\\"} 1\\n";
        add_header Content-Type text/plain;
    }
}
NGINXEOF

# Test et démarrage Nginx
log "Test et demarrage Nginx..."
nginx -t && systemctl restart nginx && systemctl enable nginx

# Service systemd pour auto-redémarrage - CORRECTION: chemin docker-compose
log "Creation service auto-redemarrage..."
cat > /etc/systemd/system/${project_name}.service << SYSTEMDEOF
[Unit]
Description=${project_name} Docker Compose
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
TimeoutStartSec=600
TimeoutStopSec=300
User=root
Environment=COMPOSE_HTTP_TIMEOUT=300

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

systemctl daemon-reload
systemctl enable ${project_name}.service

# Scripts de gestion
log "Creation scripts de gestion..."

# Script de création automatique de base
cat > /opt/${project_name}/scripts/create-odoo-db.py << 'PYTHONEOF'
#!/usr/bin/env python3
import requests
import time
import sys
import os

def wait_for_odoo(url, max_attempts=30):
    for i in range(max_attempts):
        try:
            response = requests.get(f"{url}/web/health", timeout=10)
            if response.status_code == 200:
                return True
        except Exception as e:
            print(f"Tentative {i+1}: {e}")
        time.sleep(10)
    return False

def create_database(url, master_pwd, db_name, admin_pwd, lang, country, demo):
    data = {
        'master_pwd': master_pwd,
        'name': db_name,
        'login': 'admin',
        'password': admin_pwd,
        'lang': lang,
        'country_code': country,
        'phone': '',
    }
    
    if demo:
        data['demo'] = 'true'
    
    try:
        response = requests.post(f"{url}/web/database/create", data=data, timeout=300)
        return response.status_code == 200
    except Exception as e:
        print(f"Erreur création base: {e}")
        return False

if __name__ == "__main__":
    odoo_url = "http://localhost:8069"
    master_pwd = os.getenv('MASTER_PASSWORD', '')
    db_name = os.getenv('DEFAULT_DB_NAME', 'lps_poc')
    admin_pwd = os.getenv('ADMIN_PASSWORD', 'admin')
    lang = os.getenv('DEFAULT_LANGUAGE', 'fr_FR')
    country = os.getenv('DEFAULT_COUNTRY', 'FR')
    demo = os.getenv('ENABLE_DEMO', 'true').lower() == 'true'
    
    print(f"Attente Odoo sur {odoo_url}...")
    if wait_for_odoo(odoo_url):
        print("Odoo accessible, création de la base...")
        if create_database(odoo_url, master_pwd, db_name, admin_pwd, lang, country, demo):
            print(f"Base {db_name} créée avec succès!")
            # Sauvegarder les informations
            with open('/home/ubuntu/DATABASE_INFO.txt', 'w') as f:
                f.write(f"Base de données: {db_name}\n")
                f.write(f"Utilisateur: admin\n")
                f.write(f"Mot de passe: {admin_pwd}\n")
                f.write(f"Master password: {master_pwd}\n")
                f.write(f"Langue: {lang}\n")
                f.write(f"Pays: {country}\n")
                f.write(f"Données démo: {'Oui' if demo else 'Non'}\n")
            print("Informations sauvées dans /home/ubuntu/DATABASE_INFO.txt")
        else:
            print("Erreur lors de la création de la base")
            sys.exit(1)
    else:
        print("Impossible de contacter Odoo")
        sys.exit(1)
PYTHONEOF

# Script de backup
cat > /opt/${project_name}/scripts/backup.sh << 'BACKUPEOF'
#!/bin/bash
BACKUP_DIR="/opt/${project_name}/backups"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== DEBUT SAUVEGARDE $DATE ==="

# Backup PostgreSQL complet
docker exec ${project_name}-db-${region_code} pg_dumpall -U odoo > $BACKUP_DIR/postgres_full_$DATE.sql

# Backup base spécifique si elle existe
if docker exec ${project_name}-db-${region_code} psql -U odoo -lqt | cut -d \| -f 1 | grep -qw ${default_db_name}; then
    docker exec ${project_name}-db-${region_code} pg_dump -U odoo -d ${default_db_name} > $BACKUP_DIR/${default_db_name}_$DATE.sql
fi

# Backup volumes
docker run --rm -v ${project_name}_db_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/db_volume_$DATE.tar.gz -C /data .
docker run --rm -v ${project_name}_odoo_data:/data -v $BACKUP_DIR:/backup alpine tar czf /backup/odoo_volume_$DATE.tar.gz -C /data .

# Backup configuration
tar czf $BACKUP_DIR/config_$DATE.tar.gz -C /opt/${project_name} configs/ custom-addons/

# Nettoyer anciens backups
find $BACKUP_DIR -name "*.sql" -mtime +7 -delete
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "=== SAUVEGARDE TERMINEE $DATE ==="
BACKUPEOF

# Script de monitoring
cat > /opt/${project_name}/scripts/monitor.sh << 'MONITOREOF'
#!/bin/bash
echo "=== STATUS ${project_name} ==="
echo "Date: $(date)"
echo "Timezone: $(timedatectl | grep 'Time zone')"
echo "Ubuntu: ${ubuntu_version}"
echo ""
echo "=== SERVICES ==="
systemctl status docker nginx ${project_name} --no-pager -l
echo ""
echo "=== CONTAINERS ==="
cd /opt/${project_name} && docker-compose ps
echo ""
echo "=== HEALTH CHECKS ==="
curl -s http://localhost/health
echo ""
curl -s http://localhost/metrics
echo ""
echo "=== ESPACE DISQUE ==="
df -h /opt/${project_name}
echo ""
echo "=== DERNIERS LOGS ==="
docker-compose logs --tail=10
MONITOREOF

# Rendre les scripts exécutables
chmod +x /opt/${project_name}/scripts/*.sh
chmod +x /opt/${project_name}/scripts/*.py
chown -R ubuntu:ubuntu /opt/${project_name}

# Installation pip packages pour script Python
log "Installation packages Python..."
pip3 install requests

# Vérification Docker Compose
log "Verification Docker Compose..."
docker-compose --version

# Démarrage initial
log "Demarrage initial des services..."
cd /opt/${project_name}

# Démarrage avec logs pour diagnostiquer
log "Tentative de démarrage Docker Compose..."
docker-compose up -d --remove-orphans

# Vérifier le statut immédiatement
log "Statut après démarrage..."
docker-compose ps
docker-compose logs

systemctl start ${project_name}.service

# Attente services - CORRECTION: délai plus réaliste
log "Attente demarrage services..."
for i in {1..30}; do
    if systemctl is-active --quiet ${project_name}.service; then
        log "Service ${project_name} actif"
        break
    fi
    log "Tentative $i/30..."
    sleep 20
done

# Vérification Docker containers
log "Verification containers..."
docker ps -a
cd /opt/${project_name} && docker-compose logs

# Attendre que Odoo soit complètement prêt - CORRECTION: endpoint correct
log "Attente Odoo complet..."
for i in {1..60}; do
    if curl -f http://localhost:8069/web/database/selector > /dev/null 2>&1; then
        log "Odoo operationnel"
        break
    fi
    log "Attente Odoo... ($i/60)"
    sleep 30
done

# Test final Odoo
log "Test final Odoo..."
curl -I http://localhost:8069/ || log "ERREUR: Odoo non accessible"

# Création automatique de la base si demandée
if [ "${auto_create_db}" = "true" ]; then
    log "Creation automatique de la base Odoo..."
    cd /opt/${project_name}/scripts
    MASTER_PASSWORD="${master_password}" \
    DEFAULT_DB_NAME="${default_db_name}" \
    ADMIN_PASSWORD="${admin_password}" \
    DEFAULT_LANGUAGE="${default_language}" \
    DEFAULT_COUNTRY="${default_country}" \
    ENABLE_DEMO="${enable_demo}" \
    python3 create-odoo-db.py
    
    if [ $? -eq 0 ]; then
        log "Base Odoo creee avec succes"
    else
        log "ERREUR: Echec creation base Odoo"
    fi
fi

# Configuration cron pour sauvegardes
log "Configuration sauvegardes automatiques..."
echo "0 2 * * * root /opt/${project_name}/scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/${project_name}-backup
chmod 644 /etc/cron.d/${project_name}-backup

# Vérifications finales
log "Verifications finales..."
systemctl status docker nginx ${project_name} --no-pager -l
cd /opt/${project_name} && docker-compose ps
docker logs ${project_name}-app-${region_code} --tail=20

# Message final avec toutes les informations
cat > /home/ubuntu/READY.txt << READYEOF
=== ${project_name} PRET - ${region_city} (${region_code}) ===

INFORMATIONS SYSTEME:
- Ubuntu: ${ubuntu_version}
- Timezone: ${timezone}

ACCES ODOO:
- Principal: http://VOTRE_IP_PUBLIQUE
- Direct: http://VOTRE_IP_PUBLIQUE:8069
- Health: http://VOTRE_IP_PUBLIQUE/health

CONNEXION ODOO:
- Base: ${default_db_name} $([ "${auto_create_db}" = "true" ] && echo "(créée automatiquement)" || echo "(à créer manuellement)")
- Login: admin
- Password: ${admin_password}
- Master Password: ${master_password}
- Langue: ${default_language}
- Pays: ${default_country}

SCRIPTS UTILES:
- Status: sudo /opt/${project_name}/scripts/monitor.sh
- Backup: sudo /opt/${project_name}/scripts/backup.sh
- Créer base: sudo /opt/${project_name}/scripts/create-odoo-db.py

SERVICES:
- docker.service: $(systemctl is-active docker)
- nginx.service: $(systemctl is-active nginx)
- ${project_name}.service: $(systemctl is-active ${project_name}.service)

STATUS: INSTALLATION TERMINEE - $(date)
READYEOF

# Copier informations base si créée
if [ -f "/home/ubuntu/DATABASE_INFO.txt" ]; then
    cat /home/ubuntu/DATABASE_INFO.txt >> /home/ubuntu/READY.txt
fi

chown ubuntu:ubuntu /home/ubuntu/READY.txt
chown ubuntu:ubuntu /home/ubuntu/DATABASE_INFO.txt 2>/dev/null || true

log "=== INSTALLATION TERMINEE - ${region_city} (${region_code}) ==="
log "Ubuntu: ${ubuntu_version}"
log "Services: $(systemctl is-active docker nginx ${project_name}.service)"
log "Base Odoo: $([ "${auto_create_db}" = "true" ] && echo "Créée automatiquement" || echo "À créer manuellement")"

# Log final pour diagnostic
log "=== DIAGNOSTIC FINAL ==="
log "Docker containers:"
docker ps -a
log "Docker Compose status:"
cd /opt/${project_name} && docker-compose ps
log "Ports en écoute:"
netstat -tlnp | grep -E ':(80|8069)'
log "Logs Odoo (dernières lignes):"
docker logs ${project_name}-app-${region_code} --tail=10 2>/dev/null || log "Container Odoo non trouvé"