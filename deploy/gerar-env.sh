#!/bin/sh
# Cria o .env a partir do .env.example com chaves novas.
# Não sobrescreve um .env que já existe e não mostra as chaves na tela.
set -eu
cd "$(dirname "$0")"

if [ -f .env ]; then
  echo ".env já existe. Nada foi alterado."
  exit 0
fi

command -v openssl >/dev/null 2>&1 || { echo "Instale o openssl."; exit 1; }

chave=$(openssl rand -hex 32)
usuario="admin"
senha=$(openssl rand -hex 16)

sed \
  -e "s|^WAHA_API_KEY=.*|WAHA_API_KEY=${chave}|" \
  -e "s|^WAHA_DASHBOARD_USERNAME=.*|WAHA_DASHBOARD_USERNAME=${usuario}|" \
  -e "s|^WAHA_DASHBOARD_PASSWORD=.*|WAHA_DASHBOARD_PASSWORD=${senha}|" \
  -e "s|^WHATSAPP_SWAGGER_USERNAME=.*|WHATSAPP_SWAGGER_USERNAME=${usuario}|" \
  -e "s|^WHATSAPP_SWAGGER_PASSWORD=.*|WHATSAPP_SWAGGER_PASSWORD=${senha}|" \
  .env.example > .env
chmod 600 .env

echo ".env criado com chave e senhas novas (permissão 600)."
echo "Copie WAHA_API_KEY do .env para o .env do backend."
