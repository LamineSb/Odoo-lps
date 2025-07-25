#!/bin/bash
# Installation Odoo 18 avec image Tecnativa Doodba - VERSION FINALE POUR TRIAL

set -e

echo "=== DEBUT INSTALLATION ODOO 18 DOODBA - TRIAL VERSION ==="

# Déclaration des variables avec valeurs par défaut
project_name="${PROJECT_NAME:-odoo-trial}"
region_code="${REGION_CODE:-us-east-1}"
region_city="${REGION_CITY:-virginia}"
environment="${ENVIRONMENT:-poc}"
odoo_version="${ODOO_VERSION:-18.0}"
admin_password="${ADMIN_PASSWORD:-admin123}"
db_password="${DB_PASSWORD:-odoo_trial_pwd}"
master_password="${MASTER_PASSWORD:-master_trial_pwd}"
enable_demo="${ENABLE_DEMO:-true}"
auto_create_db="${AUTO_CREATE_DB:-true}"
default_db_name="${DEFAULT_DB_NAME:-odoo_trial}"
default_language="${DEFAULT_LANGUAGE:-fr_FR}"
default_country="${DEFAULT_COUNTRY:-FR}"
timezone="${TIMEZONE:-Europe/Paris}"
postgres_version="${POSTGRES_VERSION:-15}"
max_connections="${MAX_CONNECTIONS:-50}"
shared_buffers="${SHARED_BUFFERS:-64MB}"
work_mem="${WORK_MEM:-2MB}"
ubuntu_version="${UBUNTU_VERSION:-20.04}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${region_code}] - $1"
}

log "=== CONFIGURATION TRIAL ==="
log "Projet: ${project_name}"
log "Région: ${region_city} (${region_code})"
log "Environnement: ${environment}"
log "Odoo Version: ${odoo_version}"
log "Base de données: ${default_db_name}"
log "Données démo: ${enable_demo}"
log "Timezone: ${timezone}"

# Configuration timezone
log "Configuration timezone..."
timedatectl set-timezone "${timezone}"

# Mise à jour système
log "Mise à jour Ubuntu ${ubuntu_version}..."
apt update -y && apt upgrade -y

# Installation Docker
log "Installation Docker..."
apt install -y ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-buildx-plugin
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu
docker --version || { log "ERREUR: Docker non installé correctement"; exit 1; }

# Installation Docker Compose
log "Installation Docker Compose..."
COMPOSE_VERSION="v2.30.3"
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version || { log "ERREUR: Docker Compose non installé"; exit 1; }

# Utilitaires système
log "Installation utilitaires..."
apt install -y nginx htop curl wget git jq tree vim

# Python - Installation via APT
log "Installation Python packages..."
apt install -y python3-requests python3-setuptools python3-pip
python3 -c "import requests; print('✓ Python requests OK')" || { log "ERREUR: Python requests non disponible"; exit 1; }

# Structure des dossiers
log "Création structure projet..."
mkdir -p /opt/${project_name}/{configs,scripts,backups,logs,custom-addons,private,data}
chown -R ubuntu:ubuntu /opt/${project_name}

# Configuration Odoo optimisée pour trial
log "Configuration Odoo pour Doodba..."
cat > /opt/${project_name}/configs/odoo.conf << ODOOCONF
[options]
addons_path = /opt/odoo/custom/src/private,/opt/odoo/custom/src/repos,/opt/odoo/auto/addons,/opt/odoo/addons
data_dir = /opt/odoo/data
logfile = /var/log/odoo/odoo.log
log_level = info
admin_passwd = ${master_password}
db_host = db
db_port = 5432
db_user = odoo
db_password = ${db_password}
list_db = True
db_maxconn = ${max_connections}
proxy_mode = True
xmlrpc_interface = 0.0.0.0
xmlrpc_port = 8069
workers = 0
max_cron_threads = 1
timezone = ${timezone}
default_language = ${default_language}
without_demo = $([ "${enable_demo}" = "true" ] && echo "False" || echo "True")
server_wide_modules = base,web
limit_memory_hard = 2147483648
limit_memory_soft = 1073741824
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
ODOOCONF

# Configuration des repositories Doodba
log "Configuration repos.yaml..."
cat > /opt/${project_name}/configs/repos.yaml << REPOSEOF
./odoo:
  defaults:
    depth: 1
  remotes:
    origin: https://github.com/odoo/odoo.git
  target:
    origin ${odoo_version}
  merges:
    - origin ${odoo_version}

# ./enterprise:
#   defaults:
#     depth: 1
#   remotes:
#     origin: https://github.com/odoo/enterprise.git
#   target:
#     origin ${odoo_version}
#   merges:
#     - origin ${odoo_version}
REPOSEOF

# Configuration des addons pour POC
log "Configuration addons.yaml..."
cat > /opt/${project_name}/configs/addons.yaml << ADDONSEOF
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
  - contacts
  - portal
  - payment
ADDONSEOF

# Docker Compose - Configuration optimisée pour trial
log "Configuration Docker Compose pour trial..."
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
      - ./data:/data
    command: |
      postgres
      -c max_connections=${max_connections}
      -c shared_buffers=${shared_buffers}
      -c work_mem=${work_mem}
      -c maintenance_work_mem=32MB
      -c effective_cache_size=256MB
      -c wal_buffers=8MB
      -c checkpoint_completion_target=0.9
      -c random_page_cost=1.1
      -c effective_io_concurrency=100
      -c max_wal_size=1GB
      -c min_wal_size=80MB
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U odoo"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    networks:
      - odoo_network
    labels:
      - "traefik.enable=false"

  odoo:
    image: tecnativa/doodba:18.0-20241201
    container_name: ${project_name}-app-${region_code}
    depends_on:
      db:
        condition: service_healthy
    environment:
      PGHOST: db
      PGUSER: odoo
      PGPASSWORD: ${db_password}
      PGDATABASE: postgres
      ODOO_CONF: /opt/odoo/etc/odoo.conf
      REPOS_YAML: /opt/odoo/custom/src/repos.yaml
      ADDONS_YAML: /opt/odoo/custom/src/addons.yaml
      TZ: ${timezone}
      DOODBA_ENVIRONMENT: ${environment}
      LOG_LEVEL: INFO
      ODOO_WORKERS: 0
      WITHOUT_DEMO: $([ "${enable_demo}" = "true" ] && echo "False" || echo "True")
      PYTHONOPTIMIZE: 1
      ODOO_RC: /opt/odoo/etc/odoo.conf
    volumes:
      - ./configs/odoo.conf:/opt/odoo/etc/odoo.conf:ro
      - ./configs/repos.yaml:/opt/odoo/custom/src/repos.yaml:ro
      - ./configs/addons.yaml:/opt/odoo/custom/src/addons.yaml:ro
      - odoo_data:/opt/odoo/data
      - ./logs:/var/log/odoo
      - ./custom-addons:/opt/odoo/custom/src/private
      - ./private:/opt/odoo/custom/src/private-extra
      - ./backups:/opt/odoo/backups
      - ./data:/opt/odoo/backup-data
    ports:
      - "8069:8069"
      - "8072:8072"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/health"]
      interval: 60s
      timeout: 30s
      retries: 3
      start_period: 180s
    networks:
      - odoo_network
    labels:
      - "com.docker.compose.service=odoo"
      - "environment=${environment}"
      - "region=${region_code}"

volumes:
  db_data:
    driver: local
  odoo_data:
    driver: local

networks:
  odoo_network:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
DOCKEREOF

# Correction rapportée ici : tous les \$ des variables Nginx sont bien échappés !
log "Configuration Nginx reverse proxy..."
cat > /etc/nginx/sites-available/default << NGINXEOF
upstream odoo {
    server 127.0.0.1:8069;
}
upstream odoochat {
    server 127.0.0.1:8072;
}
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    add_header Referrer-Policy "strict-origin-when-cross-origin";
    add_header X-Region "${region_code}" always;
    add_header X-City "${region_city}" always;
    add_header X-Environment "${environment}" always;
    add_header X-Project "${project_name}" always;
    add_header X-Odoo-Version "18.0-doodba-trial" always;
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json image/svg+xml;
    client_max_body_size 50M;
    location / {
        proxy_pass http://odoo;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$server_name;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        proxy_buffer_size 64k;
        proxy_buffers 4 64k;
        proxy_busy_buffers_size 64k;
        proxy_temp_file_write_size 64k;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    location /longpolling {
        proxy_pass http://odoochat;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://odoo;
        proxy_cache_valid 200 302 1h;
        proxy_cache_valid 404 1m;
        add_header Cache-Control "public, max-age=3600";
        expires 1h;
    }
    location /health {
        access_log off;
        return 200 "OK - ${project_name} Trial - ${region_city} (${region_code}) - \$(date)";
        add_header Content-Type text/plain;
    }
    location /status {
        access_log off;
        return 200 "READY - ${project_name} - Odoo 18.0 Trial - \$(date)";
        add_header Content-Type text/plain;
    }
    location /metrics {
        access_log off;
        return 200 "# HELP odoo_status Odoo Trial Status\\n# TYPE odoo_status gauge\\nodoo_status{version=\\"18.0\\",image=\\"doodba-trial\\",region=\\"${region_code}\\",environment=\\"${environment}\\"} 1\\n";
        add_header Content-Type text/plain;
    }
    location /trial-info {
        access_log off;
        return 200 "=== ODOO 18 TRIAL INFO ===\\nProject: ${project_name}\\nRegion: ${region_city} (${region_code})\\nEnvironment: ${environment}\\nDatabase: ${default_db_name}\\nDemo Data: ${enable_demo}\\nAccess: http://\$host\\nLogin: admin\\n";
        add_header Content-Type text/plain;
    }
}
NGINXEOF

# Test et activation Nginx
log "Test et activation Nginx..."
nginx -t && systemctl restart nginx && systemctl enable nginx

# Service systemd pour gestion automatique
log "Création service systemd..."
cat > /etc/systemd/system/${project_name}.service << SYSTEMDEOF
[Unit]
Description=${project_name} Odoo 18.0 Trial
Documentation=https://www.odoo.com/documentation/18.0/
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/${project_name}
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
ExecReload=/usr/local/bin/docker-compose restart
TimeoutStartSec=900
TimeoutStopSec=300
User=root
Group=root
Environment=COMPOSE_HTTP_TIMEOUT=600
Environment=COMPOSE_PROJECT_NAME=${project_name}
Restart=on-failure
RestartSec=30s

[Install]
WantedBy=multi-user.target
SYSTEMDEOF

systemctl daemon-reload
systemctl enable ${project_name}.service

# ==== Suivent les scripts python et .sh, aucune modification requise ici ====

# --- SCRIPTS UTILITAIRES (copier ton bloc existant pour create-database.py et monitor.sh, aucun $ nginx dedans) ---

(...)

# Rendre les scripts exécutables
chmod +x /opt/${project_name}/scripts/*.py
chmod +x /opt/${project_name}/scripts/*.sh
chown -R ubuntu:ubuntu /opt/${project_name}

# Démarrage des services
log "Démarrage des services Docker..."
cd /opt/${project_name}

log "Téléchargement des images Docker..."
docker-compose pull

log "Démarrage des conteneurs..."
docker-compose up -d --remove-orphans

sleep 15
log "Vérification des conteneurs..."
docker-compose ps

systemctl start ${project_name}.service

log "Attente de la disponibilité des services (peut prendre 3-5 minutes)..."
for i in {1..60}; do
    if systemctl is-active --quiet ${project_name}.service; then
        log "✓ Service systemd actif"
        break
    fi
    log "Attente du service systemd... ($i/60)"
    sleep 15
done

log "Attente de la disponibilité d'Odoo..."
for i in {1..90}; do
    if curl -f -s http://localhost:8069/web/database/selector > /dev/null 2>&1; then
        log "✓ Odoo est accessible!"
        break
    fi
    log "Attente d'Odoo... ($i/90)"
    sleep 20
done

log "Tests de connectivité finale..."
echo "Nginx:" $(curl -s -w "%{http_code}" http://localhost/health -o /dev/null)
echo "Odoo:" $(curl -s -w "%{http_code}" http://localhost:8069/web/health -o /dev/null 2>/dev/null || echo "N/A")

if [ "${auto_create_db}" = "true" ]; then
    log "Création automatique de la base de données..."
    cd /opt/${project_name}/scripts
    export MASTER_PASSWORD="${master_password}"
    export DEFAULT_DB_NAME="${default_db_name}"
    export ADMIN_PASSWORD="${admin_password}"
    export DEFAULT_LANGUAGE="${default_language}"
    export DEFAULT_COUNTRY="${default_country}"
    export ENABLE_DEMO="${enable_demo}"
    python3 create-database.py
    if [ $? -eq 0 ]; then
        log "✓ Base de données créée avec succès!"
    else
        log "⚠ Création de base échouée - vous pouvez la créer manuellement"
    fi
fi

# Configuration des tâches automatiques
log "Configuration des tâches automatiques..."
cat > /etc/cron.d/${project_name}-maintenance << CRONEOF
0 2 * * 0 root cd /opt/${project_name} && docker-compose exec -T db pg_dumpall -U odoo | gzip > /opt/${project_name}/backups/weekly_backup_\$(date +\\%Y\\%m\\%d).sql.gz
0 8 * * * root /opt/${project_name}/scripts/monitor.sh >> /var/log/${project_name}-monitor.log 2>&1
0 3 1 * * root find /opt/${project_name}/logs -name "*.log" -mtime +30 -delete
CRONEOF

chmod 644 /etc/cron.d/${project_name}-maintenance

log "=========================================="
log "INSTALLATION ODOO 18 TRIAL TERMINÉE"
log "=========================================="
log "Projet: ${project_name}"
log "Région: ${region_city} (${region_code})"
log "Environnement: ${environment}"
log "Base de données: ${default_db_name}"
log "Données de démo: ${enable_demo}"
log ""
log "ACCÈS:"
log "- URL locale: http://localhost"
log "- URL publique: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'VOTRE_IP_PUBLIQUE')"
log "- Port Odoo direct: 8069"
log ""
log "MONITORING:"
log "- Status: /opt/${project_name}/scripts/monitor.sh"
log "- Logs: docker-compose logs -f"
log "- Service: systemctl status ${project_name}"
log ""
log "INFORMATIONS DE CONNEXION:"
log "- Fichier: /home/ubuntu/ODOO_TRIAL_INFO.txt"
log "- Login par défaut: admin"
log "- Mot de passe: ${admin_password}"
log ""
log "Pour surveiller l'installation:"
log "sudo tail -f /var/log/syslog"
log "docker-compose logs -f"
log ""
log "=========================================="
log "INSTALLATION TERMINÉE - ODOO 18 TRIAL PRÊT!"
log "=========================================="
