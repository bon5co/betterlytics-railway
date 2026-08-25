# Betterlytics for Railway - application service (nginx + Rust ingest + Next.js dashboard).
#
# Pinned to an upstream release rather than :latest, because every boot runs
# `prisma migrate deploy` and `clickhouse-migrations` forward with no downgrade
# path.
FROM ghcr.io/betterlytics/betterlytics-selfhost:v1.3.5

# DB-IP Lite country database, baked so that the Geography breakdown works on a
# fresh deploy with no MaxMind account. CC BY 4.0 - attribution is in the README
# and on the template listing.
ARG DBIP_URL=https://download.db-ip.com/free/dbip-country-lite-2026-08.mmdb.gz
RUN set -eux; \
    mkdir -p /app/backend/assets/geoip; \
    curl -fsSL "$DBIP_URL" -o /tmp/geoip.mmdb.gz; \
    gzip -dc /tmp/geoip.mmdb.gz > /app/backend/assets/geoip/GeoLite2-Country.mmdb; \
    rm -f /tmp/geoip.mmdb.gz; \
    test -s /app/backend/assets/geoip/GeoLite2-Country.mmdb

COPY nginx.conf /etc/nginx/templates/nginx.conf
COPY supervisord.conf /etc/supervisor/conf.d/betterlytics.conf
COPY seed-admin.js /usr/local/bin/seed-admin.js
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Literals live here rather than in template variables: `templateGenerate` drops
# a literal defaultValue, so anything shipped as a variable with a literal value
# publishes as a blank required field on the deploy form.
ENV HTTP_SCHEME=http \
    FORCE_HTTP_SCHEME=https \
    PORT=8080 \
    SERVER_HOST=127.0.0.1 \
    SERVER_PORT=3001 \
    LOG_LEVEL=info \
    DATA_RETENTION_DAYS=365 \
    CLICKHOUSE_DB=analytics \
    CLICKHOUSE_USER=admin \
    CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    CLICKHOUSE_BACKEND_USER=backend \
    CLICKHOUSE_DASHBOARD_USER=dashboard \
    POSTGRES_DB=postgres \
    POSTGRES_USER=postgres \
    ENABLE_GEOLOCATION=true \
    GEOIP_DB_PATH=/app/backend/assets/geoip/GeoLite2-Country.mmdb \
    ENABLE_REGISTRATION=false

EXPOSE 8080

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
