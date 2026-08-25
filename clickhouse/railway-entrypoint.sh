#!/bin/bash
set -e

die() { echo "[clickhouse] $1" >&2; exit 1; }

[ -n "$CLICKHOUSE_PASSWORD" ] || die "CLICKHOUSE_PASSWORD is required."
[ -n "$CLICKHOUSE_BACKEND_PASSWORD" ] || die "CLICKHOUSE_BACKEND_PASSWORD is required."
[ -n "$CLICKHOUSE_DASHBOARD_PASSWORD" ] || die "CLICKHOUSE_DASHBOARD_PASSWORD is required."

# Size the query thread pool from the container's CPU quota. Upstream's
# self-host config hardcodes max_threads=1 for every deploy regardless of plan.
CPU_MAX="/sys/fs/cgroup/cpu.max"
THREADS=1
if [ -r "$CPU_MAX" ]; then
    read -r quota period < "$CPU_MAX" || true
    if [ "$quota" != "max" ] && [ -n "$period" ] && [ "$period" -gt 0 ] 2>/dev/null; then
        THREADS=$(( quota / period ))
    else
        THREADS=$(nproc)
    fi
fi
[ "$THREADS" -ge 1 ] 2>/dev/null || THREADS=1
echo "[clickhouse] sizing max_threads=${THREADS} from ${CPU_MAX}"
cat > /etc/clickhouse-server/config.d/railway-threads.xml <<XML
<clickhouse>
    <profiles>
        <default>
            <max_threads>${THREADS}</max_threads>
        </default>
    </profiles>
</clickhouse>
XML

/usr/local/bin/reconcile-users.sh &

exec /entrypoint.sh "$@"
