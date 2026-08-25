# ClickHouse for Betterlytics on Railway.
FROM clickhouse/clickhouse-server:25.8

COPY config.d/betterlytics.xml /etc/clickhouse-server/config.d/betterlytics.xml
COPY reconcile-users.sh /usr/local/bin/reconcile-users.sh
COPY railway-entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /usr/local/bin/reconcile-users.sh /railway-entrypoint.sh

ENV CLICKHOUSE_DB=analytics \
    CLICKHOUSE_USER=admin \
    CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1 \
    CLICKHOUSE_BACKEND_USER=backend \
    CLICKHOUSE_DASHBOARD_USER=dashboard

EXPOSE 8123 9000

ENTRYPOINT ["/bin/bash", "/railway-entrypoint.sh"]
