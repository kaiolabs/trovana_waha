# WAHA da Trovana (Grupos no Automático)

Sobe o WAHA Core com o motor GOWS para o backend da Trovana enviar ofertas nos grupos de WhatsApp.
Esta pasta é só nossa. O código do WAHA (upstream) não é alterado: usamos a imagem oficial e falamos com ele pela API.

| Arquivo | Para que serve |
|---|---|
| `docker-compose.yml` | O WAHA, e o Caddy (HTTPS) opcional |
| `.env.example` | Modelo das variáveis |
| `gerar-env.sh` | Cria o `.env` com a chave e as senhas novas |
| `Caddyfile` | HTTPS com certificado automático e lista de IPs liberados |
| `backup.sh` | Copia o volume das sessões |

## No Coolify (produção da Trovana)

Use o `docker-compose.coolify.yml`. Ele não publica porta nenhuma, porque o Traefik do Coolify cuida do HTTPS.

1. Crie o recurso: New Resource > Docker Compose (Empty) e cole o `docker-compose.coolify.yml`.
2. No serviço `waha`, preencha o domínio com `https://waha.trovana.com.br:3000`. O `:3000` é a porta interna, e o endereço público continua sem porta.
3. Em Environment Variables, cole a seção 1 do `coolify.env`. Esse arquivo é local, não vai para o git e contém as chaves.
4. Clique em Deploy e espere ficar `healthy`.
5. No recurso do backend (API, worker e beat), cole a seção 2 do `coolify.env` e reimplante.
6. Teste do seu computador:
   - `curl https://waha.trovana.com.br/ping` deve responder `pong`;
   - `/api/sessions` sem a chave deve responder 401.

Na Cloudflare, use o modo SSL/TLS "Full (strict)", o mesmo dos outros domínios que já passam pelo proxy.
O backup e a atualização seguem as seções abaixo; no Coolify, o volume tem o prefixo do recurso (veja com `docker volume ls | grep waha`).

## Servidor

| Clientes conectados | Máquina |
|---|---|
| Até ~50 | 2 vCPU, 4 GB de RAM, 40 GB SSD |
| Até ~150 | 4 vCPU, 8 GB de RAM |
| Mais que isso | Um segundo servidor |

- Ubuntu 22.04 ou 24.04, com Docker e o plugin `docker compose`.
- De preferência num datacenter no Brasil, e com IP fixo e só seu.
- Medido: o WAHA ligado sem sessão usa cerca de 200 a 400 MB de RAM. Meça de novo com as primeiras sessões reais e ajuste `WAHA_MEMORY_LIMIT`.
- Servidor ARM (Oracle Ampere): troque `WAHA_IMAGE` para `devlikeapro/waha:gows-arm-2026.9.2`.

## Subir

```bash
git clone git@github.com:kaiolabs/trovana_waha.git
cd trovana_waha/deploy
./gerar-env.sh
nano .env
docker compose up -d
docker compose ps
```

No `nano .env`, ajuste o que for do seu cenário (veja abaixo). O `gerar-env.sh` não mostra as chaves na tela.
O `docker compose ps` deve mostrar `healthy` em até 1 minuto.

## Como o backend chega no WAHA

Escolha **um** cenário.

### A. Backend no mesmo servidor, rodando direto (fora do Docker)

- `.env` do WAHA: `WAHA_BIND=127.0.0.1`.
- Backend: `WAHA_URL=http://127.0.0.1:3000`.

### B. Backend no mesmo servidor, em contêiner (Coolify, outro compose)

Coloque o contêiner do backend (e o do worker Celery) na rede `trovana_waha`:

```bash
docker network connect trovana_waha NOME_DO_CONTEINER_DO_BACKEND
```

- Backend: `WAHA_URL=http://trovana-waha:3000`.
- No Coolify, adicione a rede `trovana_waha` como rede externa do serviço para não perder a ligação ao reimplantar.
- A porta continua só em `127.0.0.1`, sem nada exposto para fora.

### C. Backend em outro servidor (HTTPS)

1. Crie um registro DNS A, ex. `waha.trovana.cloudflow.com.br`, apontando para este servidor.
2. No `.env`:
   - `WAHA_DOMAIN=waha.trovana.cloudflow.com.br`
   - `WAHA_ALLOWED_IPS=` com o IP de saída do servidor do backend (vários separados por espaço)
   - `WAHA_BASE_URL=https://waha.trovana.cloudflow.com.br`
   - mantenha `WAHA_BIND=127.0.0.1`
3. Suba com o Caddy: `docker compose --profile https up -d`
4. Backend: `WAHA_URL=https://waha.trovana.cloudflow.com.br`

O Caddy precisa das portas 80 e 443 livres. Se já houver Traefik/Coolify nelas, use o cenário B ou crie o domínio pelo próprio Coolify.

## Variáveis no backend

No `.env` do backend (`trovana_back`):

```
WHATSAPP_PROVIDER=waha
WAHA_URL=            # do cenário acima
WAHA_API_KEY=        # o mesmo valor do .env do WAHA
WHATSAPP_WEBHOOK_BASE_URL=https://back.trovana.cloudflow.com.br
WHATSAPP_WEBHOOK_SECRET=   # openssl rand -hex 32 (só o backend usa)
```

O webhook é configurado sessão por sessão pelo próprio backend. Não precisa configurar nada de webhook aqui.
Depois de mudar o `.env` do backend, reinicie a API, o worker e o beat do Celery.

## Firewall

```bash
sudo ufw default deny incoming
sudo ufw allow OpenSSH
sudo ufw enable
```

Para o cenário C, adicione `sudo ufw allow 80,443/tcp`.

Atenção: portas publicadas pelo Docker passam por fora do UFW. Por isso a porta do WAHA fica em `127.0.0.1` em todos os cenários. Não troque para `0.0.0.0`.

## Dia a dia

```bash
docker compose logs -f waha
docker compose ps
docker compose restart waha
```

Reiniciar não desconecta ninguém: as sessões ficam no volume `trovana_waha_sessions` e religam sozinhas.

**Nunca** rode `docker compose down -v`. O `-v` apaga o volume e todos os clientes precisam conectar o WhatsApp de novo.

## Backup

```bash
./backup.sh
```

- Guarda os 14 mais recentes em `deploy/backups/`.
- Agende no cron às 4h: `0 4 * * * /caminho/trovana_waha/deploy/backup.sh`
- A cópia é feita com o WAHA ligado. Para uma cópia garantida, pare antes com `docker compose stop waha` e ligue depois com `docker compose start waha`.
- Guarde uma cópia fora do servidor. O arquivo dá acesso aos WhatsApps conectados: trate como senha.

Restaurar (com o WAHA parado):

```bash
docker compose stop waha
docker run --rm -v trovana_waha_sessions:/dados -v "$PWD/backups:/backup" alpine:3.20 sh -c "rm -rf /dados/* && tar xzf /backup/ARQUIVO.tar.gz -C /dados"
docker compose start waha
```

## Atualizar o WAHA

1. Veja a nova versão em https://hub.docker.com/r/devlikeapro/waha/tags (tag `gows-AAAA.M.N`).
2. Rode `./backup.sh`.
3. Troque `WAHA_IMAGE` no `.env`.
4. Rode `docker compose pull && docker compose up -d`.
5. Confira com `docker compose ps` e na tela de admin Grupos da Trovana se os números continuam conectados.

Não use a tag `latest`: uma atualização sem teste pode derrubar todas as sessões.

## Depurar

Para abrir o painel e o Swagger do WAHA temporariamente:

1. No `.env`, use `WAHA_DASHBOARD_ENABLED=True` e `WHATSAPP_SWAGGER_ENABLED=True`. O usuário e a senha já foram gerados pelo `gerar-env.sh`.
2. Rode `docker compose up -d`.
3. No seu computador, abra o túnel com `ssh -L 3000:127.0.0.1:3000 usuario@servidor`.
4. Acesse http://localhost:3000/dashboard.

Desligue de novo quando terminar.
