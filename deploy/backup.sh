#!/bin/sh
# Copia o volume das sessões para backups/ (mantém os 14 mais recentes).
# Agende no cron, ex.: 0 4 * * * /caminho/deploy/backup.sh
# No Coolify o volume tem prefixo: WAHA_VOLUME=<nome> ./backup.sh
set -eu
cd "$(dirname "$0")"
mkdir -p backups
arquivo="sessions-$(date +%Y%m%d-%H%M%S).tar.gz"

docker run --rm \
  -v "${WAHA_VOLUME:-trovana_waha_sessions}":/dados:ro \
  -v "$(pwd)/backups:/backup" \
  alpine:3.20 tar czf "/backup/${arquivo}" -C /dados .

chmod 600 "backups/${arquivo}"
ls -1t backups/sessions-*.tar.gz | tail -n +15 | xargs -r rm -f
echo "Backup salvo em backups/${arquivo}"
