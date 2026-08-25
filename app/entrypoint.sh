#!/bin/bash
set -e

export PATH="/app/initializer/node_modules/.bin:$PATH"
export NODE_PATH="/app/dashboard/node_modules:/app/initializer/node_modules"
export PORT="${PORT:-8080}"

die() { echo "[betterlytics] $1" >&2; exit 1; }

[ -n "$DOMAIN" ] || die "DOMAIN is required (hostname only, no scheme)."
[ -n "$NEXTAUTH_SECRET" ] || die "NEXTAUTH_SECRET is required."
[ -n "$ADMIN_EMAIL" ] || die "ADMIN_EMAIL is required; refusing to boot an instance with no administrator."
[ -n "$ADMIN_PASSWORD" ] || die "ADMIN_PASSWORD is required; refusing to boot an instance with no administrator."
[ -n "$POSTGRES_PASSWORD" ] || die "POSTGRES_PASSWORD is required."
[ -n "$CLICKHOUSE_BACKEND_PASSWORD" ] || die "CLICKHOUSE_BACKEND_PASSWORD is required."
[ -n "$CLICKHOUSE_DASHBOARD_PASSWORD" ] || die "CLICKHOUSE_DASHBOARD_PASSWORD is required."
[ -n "$CLICKHOUSE_PASSWORD" ] || die "CLICKHOUSE_PASSWORD is required."

# TOTP_SECRET_ENCRYPTION_KEY is validated as exactly 32 characters by the
# dashboard's zod schema, which is parsed at module import: a wrong length is a
# crash loop, not a warning.
if [ -n "$TOTP_SECRET_ENCRYPTION_KEY" ] && [ "${#TOTP_SECRET_ENCRYPTION_KEY}" -ne 32 ]; then
    die "TOTP_SECRET_ENCRYPTION_KEY must be exactly 32 characters (got ${#TOTP_SECRET_ENCRYPTION_KEY})."
fi

PG_HOST="${POSTGRES_HOST:-postgres.railway.internal}"
CH_HOST="${CLICKHOUSE_HOST:-clickhouse.railway.internal}"
PG_PORT="${POSTGRES_PORT:-5432}"
CH_PORT="${CLICKHOUSE_PORT:-8123}"

export POSTGRES_DB="${POSTGRES_DB:-dashboard}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_SITECONFIG_RO_PASSWORD="${POSTGRES_SITECONFIG_RO_PASSWORD:-$POSTGRES_PASSWORD}"

export POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${PG_HOST}:${PG_PORT}/${POSTGRES_DB}?schema=public"
export SITE_CONFIG_DATABASE_URL="postgresql://siteconfig_ro:${POSTGRES_SITECONFIG_RO_PASSWORD}@${PG_HOST}:${PG_PORT}/${POSTGRES_DB}"
export CLICKHOUSE_URL="http://${CH_HOST}:${CH_PORT}"
export CLICKHOUSE_DB="${CLICKHOUSE_DB:-analytics}"
export CLICKHOUSE_USER="${CLICKHOUSE_USER:-admin}"
export CLICKHOUSE_BACKEND_USER="${CLICKHOUSE_BACKEND_USER:-backend}"
export CLICKHOUSE_DASHBOARD_USER="${CLICKHOUSE_DASHBOARD_USER:-dashboard}"

export FORCE_HTTP_SCHEME="${FORCE_HTTP_SCHEME:-https}"
export PUBLIC_BASE_URL="${FORCE_HTTP_SCHEME}://${DOMAIN}"
export NEXTAUTH_URL="${PUBLIC_BASE_URL}"
export PUBLIC_ANALYTICS_BASE_URL="${PUBLIC_BASE_URL}"
export PUBLIC_TRACKING_SERVER_ENDPOINT="${PUBLIC_BASE_URL}"
export SSL_DOMAIN="${DOMAIN}"

# Geolocation: the DB-IP Lite country database is baked into the image, so the
# Geography breakdown works on a fresh deploy with no MaxMind account. The
# v1.3.5 updater returns early without MaxMind credentials, so it never
# overwrites the baked file.
export ENABLE_GEOLOCATION="${ENABLE_GEOLOCATION:-true}"
export GEOIP_DB_PATH="${GEOIP_DB_PATH:-/app/backend/assets/geoip/GeoLite2-Country.mmdb}"

wait_for() {
    host="$1"; port="$2"; name="$3"; i=0
    while [ "$i" -lt 60 ]; do
        if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
            echo "[betterlytics] $name is reachable at $host:$port"
            return 0
        fi
        i=$((i + 1))
        echo "[betterlytics] waiting for $name at $host:$port ($i/60)..."
        sleep 3
    done
    die "timed out waiting for $name at $host:$port"
}

wait_for "$PG_HOST" "$PG_PORT" "Postgres"
wait_for "$CH_HOST" "$CH_PORT" "ClickHouse"

run_with_retry() {
    label="$1"; shift; n=0
    until [ "$n" -ge 15 ]; do
        echo "[betterlytics] $label (attempt $((n + 1))/15)..."
        if "$@"; then return 0; fi
        n=$((n + 1))
        sleep 4
    done
    die "$label failed after 15 attempts"
}

cd /app/initializer
run_with_retry "ClickHouse migrations" env NODE_ENV=production node scripts/run-migration.js
run_with_retry "PostgreSQL migrations" prisma migrate deploy --schema /app/initializer/prisma/schema.prisma

echo "[betterlytics] running post-migration scripts..."
node scripts/post_migrate_siteconfig_ro.js
node scripts/post_migrate_monitoring_ro.js

# Seed the administrator while nothing is listening on the public port. A
# dashboard started here binds loopback only; nginx is not running yet, so the
# instance is unreachable from outside until the account exists.
echo "[betterlytics] seeding the administrator before the public port opens..."
cd /app/dashboard
NODE_ENV=production HOSTNAME=127.0.0.1 PORT=3000 node /app/dashboard/server.js &
SEED_PID=$!

i=0
until [ "$i" -ge 60 ]; do
    if (echo >/dev/tcp/127.0.0.1/3000) >/dev/null 2>&1; then break; fi
    i=$((i + 1))
    sleep 2
done
[ "$i" -lt 60 ] || die "the dashboard never came up on loopback; cannot seed the administrator"

set +e
node /usr/local/bin/seed-admin.js
SEED_RC=$?
set -e

kill "$SEED_PID" 2>/dev/null || true
wait "$SEED_PID" 2>/dev/null || true

[ "$SEED_RC" -eq 0 ] || die "administrator seeding failed; refusing to open the public port"

echo "[betterlytics] configuring nginx on port ${PORT} (TLS is terminated by Railway)..."
export PORT
envsubst '${PORT}' < /etc/nginx/templates/nginx.conf > /etc/nginx/conf.d/default.conf

echo "[betterlytics] starting services..."
rm -f /run/betterlytics-fatal
/usr/bin/supervisord -c /etc/supervisor/conf.d/betterlytics.conf
rc=$?

if [ -f /run/betterlytics-fatal ]; then
    echo "[betterlytics] $(cat /run/betterlytics-fatal) died permanently; exiting non-zero so the deploy fails"
    exit 1
fi

exit "$rc"
