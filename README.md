# betterlytics-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/betterlytics-or-just-updated-cookieless-?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [Betterlytics template](https://railway.com/deploy/betterlytics-or-just-updated-cookieless-?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

Railway wrapper images for [Betterlytics](https://github.com/betterlytics/betterlytics), the
cookieless, privacy-first web analytics platform (a self-hosted Plausible / Google Analytics
alternative backed by ClickHouse).

Two images are published from this repository:

| Image | Base | Purpose |
| --- | --- | --- |
| `ghcr.io/bon5co/betterlytics-railway` | `ghcr.io/betterlytics/betterlytics-selfhost:v1.3.5` | nginx + the Rust ingest backend + the Next.js dashboard under supervisord |
| `ghcr.io/bon5co/betterlytics-railway-clickhouse` | `clickhouse/clickhouse-server:25.8` | ClickHouse with the analytics SQL users reconciled on every boot |

## Why the wrapper exists

Upstream's self-host image is built for Docker Compose, where ClickHouse gets **two** volumes: one
for `/var/lib/clickhouse` and a second for `/etc/clickhouse-server/users.d`. A Railway service has
exactly one volume, and upstream's ClickHouse config points its `user_directories/local_directory`
at `users.d` — which lives in the image layer. The `backend` and `dashboard` SQL users are created
once by `init-users.sh` (which only runs against an empty data directory) and are therefore **lost
on the first redeploy**, after which the ingest backend loops on:

```
Invalid database schema: bad response: Code: 516. DB::Exception: backend: Authentication failed:
password is incorrect, or there is no user with such name.
```

The service still reports a successful deploy, so nothing surfaces the failure except an analytics
instance that silently records nothing.

`clickhouse/reconcile-users.sh` runs on every boot and re-applies both users, their roles and their
grants, so the deployment survives redeploys. The `app` image additionally:

- seeds the administrator account **before** nginx opens the public port, and re-applies the
  password on every boot, so a redeploy is a working password reset;
- refuses to boot when any required credential is empty;
- ships a country-level GeoIP database so the dashboard's country reporting works out of the box;
- rate-limits `/event` per client, keyed on the first address of `X-Forwarded-For` (Railway's edge
  hop rotates per request, so the whole header is not a usable key);
- sizes ClickHouse's `max_threads` from the container's cgroup CPU quota.

## Environment

The app image requires `DOMAIN`, `NEXTAUTH_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`,
`POSTGRES_PASSWORD`, `CLICKHOUSE_PASSWORD`, `CLICKHOUSE_BACKEND_PASSWORD`,
`CLICKHOUSE_DASHBOARD_PASSWORD` and a 32-character `TOTP_SECRET_ENCRYPTION_KEY`. The ClickHouse
image requires the three ClickHouse passwords. Hosts default to Railway's private domains and can
be overridden with `POSTGRES_HOST` / `CLICKHOUSE_HOST`.

## Licences and attribution

Betterlytics is licensed AGPL-3.0; these images redistribute it unmodified apart from the
configuration described above.

The bundled IP-to-country database is [IP Geolocation by DB-IP](https://db-ip.com), licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
