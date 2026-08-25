#!/bin/bash
# Recreates the two SQL users the Betterlytics backend and dashboard log in with,
# on every boot, as the admin user.
#
# The stock ClickHouse image runs /docker-entrypoint-initdb.d only when the data
# directory is empty, so a first-boot-only script cannot survive anything. The
# access directory is on the volume here, so these users normally persist by
# themselves; this runs anyway so that a lost or corrupted access directory
# repairs itself instead of taking ingest down.
set -e

CH_USER="${CLICKHOUSE_USER:-admin}"
CH_DB="${CLICKHOUSE_DB:-analytics}"
BACKEND_USER="${CLICKHOUSE_BACKEND_USER:-backend}"
DASHBOARD_USER="${CLICKHOUSE_DASHBOARD_USER:-dashboard}"

q() { clickhouse-client --host 127.0.0.1 --user "$CH_USER" --password "$CLICKHOUSE_PASSWORD" --query "$1"; }

i=0
until [ "$i" -ge 60 ]; do
    if q "SELECT 1" >/dev/null 2>&1; then break; fi
    i=$((i + 1))
    sleep 2
done
if [ "$i" -ge 60 ]; then
    echo "[reconcile-users] ClickHouse did not accept an admin connection; users NOT reconciled" >&2
    exit 1
fi

q "CREATE DATABASE IF NOT EXISTS ${CH_DB}"

# CREATE USER OR REPLACE drops the user's grants, so the roles and grants are
# always re-applied after it.
q "CREATE USER OR REPLACE ${BACKEND_USER} IDENTIFIED BY '${CLICKHOUSE_BACKEND_PASSWORD}'"
q "CREATE USER OR REPLACE ${DASHBOARD_USER} IDENTIFIED BY '${CLICKHOUSE_DASHBOARD_PASSWORD}'"
q "CREATE ROLE IF NOT EXISTS backend_role"
q "CREATE ROLE IF NOT EXISTS dashboard_role"
q "GRANT SELECT ON ${CH_DB}.*, INSERT ON ${CH_DB}.*, ALTER ON ${CH_DB}.*, CREATE VIEW ON ${CH_DB}.*, CREATE TABLE ON ${CH_DB}.*, SELECT ON system.databases, SELECT ON system.tables TO backend_role"
q "GRANT SELECT ON ${CH_DB}.* TO dashboard_role"
q "GRANT backend_role TO ${BACKEND_USER}"
q "GRANT dashboard_role TO ${DASHBOARD_USER}"

echo "[reconcile-users] ${BACKEND_USER} and ${DASHBOARD_USER} are present with their grants"
