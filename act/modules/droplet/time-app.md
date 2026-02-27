# docker-compose.yml (Droplet - producao)
#
# arquitetura:
#   - app: django ninja (porta 8000)
#   - keycloak: auth server sidecar (porta 8080)
#   - worker: outbox dispatcher (sem porta)
#   - todos stateless - persistencia no PostgreSQL Managed da DigitalOcean
#   - cache/filas no Valkey Managed da DigitalOcean
#
# credenciais:
#   - preencher .env com terraform output (ver .env.example)
#
# como rodar:
#   - cp .env.example .env
#   - preencher .env com valores do terraform output
#   - docker compose up -d
#
# logs:
#   - docker compose logs -f
#   - docker compose logs -f keycloak
#   - docker compose logs -f app

services:
  app:
    image: ${APP_IMAGE}
    restart: unless-stopped
    env_file: .env
    environment:
      DATABASE_URL: ${APP_POOL_URI}
      VALKEY_URL: ${VALKEY_URI}
      KEYCLOAK_URL: http://keycloak:8080
    ports:
      - "127.0.0.1:8000:8000"
    depends_on:
      keycloak:
        condition: service_healthy

  keycloak:
    image: quay.io/keycloak/keycloak:26.0
    restart: unless-stopped
    command: start --optimized
    environment:
      KC_DB: postgres
      KC_DB_URL: ${KEYCLOAK_JDBC_URI}
      KC_HOSTNAME: ${KEYCLOAK_HOSTNAME}
      KC_PROXY_HEADERS: xforwarded
      KC_HTTP_ENABLED: "true"
      KC_HEALTH_ENABLED: "true"
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD}
    ports:
      - "127.0.0.1:8080:8080"
    healthcheck:
      test: ["CMD-SHELL", "exec 3<>/dev/tcp/127.0.0.1/9000;echo -e 'GET /health/ready HTTP/1.1\r\nhost: localhost\r\nConnection: close\r\n\r\n' >&3;if timeout 5 grep -q '200 OK' <&3; then exit 0; else exit 1; fi"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  worker:
    image: ${APP_IMAGE}
    restart: unless-stopped
    command: python -m workers.dispatcher
    env_file: .env
    environment:
      DATABASE_URL: ${APP_POOL_URI}
      VALKEY_URL: ${VALKEY_URI}
    depends_on:
      - app