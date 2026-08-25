/*
 * Seeds and rotates the Betterlytics dashboard administrator.
 *
 * Runs against a dashboard bound to loopback, before nginx opens the public
 * port, so the first request the internet ever serves is against a claimed
 * instance.
 *
 * Seeding goes through the app's own NextAuth credentials route rather than a
 * raw INSERT, because `events.createUser` in dashboard/src/lib/auth.ts also
 * creates the starter subscription and the default user settings; a hand-rolled
 * row would skip both. Rotation is done in SQL, because upstream's
 * `attemptAdminInitialization` returns null once an administrator exists and the
 * product exposes no other password-change path that works without SMTP.
 */
const { Client } = require('pg');
const bcrypt = require('bcrypt');

const EMAIL = process.env.ADMIN_EMAIL;
const PASSWORD = process.env.ADMIN_PASSWORD;
const BASE = process.env.SEED_BASE_URL || 'http://127.0.0.1:3000';
const SALT_ROUNDS = 10;

function parseCookies(res, jar) {
  const raw = res.headers.getSetCookie ? res.headers.getSetCookie() : [];
  for (const c of raw) {
    const [pair] = c.split(';');
    const idx = pair.indexOf('=');
    if (idx > 0) jar[pair.slice(0, idx).trim()] = pair.slice(idx + 1).trim();
  }
}

function cookieHeader(jar) {
  return Object.entries(jar).map(([k, v]) => `${k}=${v}`).join('; ');
}

async function createViaCredentials() {
  const jar = {};
  const csrfRes = await fetch(`${BASE}/api/auth/csrf`);
  parseCookies(csrfRes, jar);
  const { csrfToken } = await csrfRes.json();

  const body = new URLSearchParams({
    csrfToken,
    email: EMAIL,
    password: PASSWORD,
    redirect: 'false',
    json: 'true',
  });

  const res = await fetch(`${BASE}/api/auth/callback/credentials`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Cookie: cookieHeader(jar),
    },
    body,
    redirect: 'manual',
  });
  return res.status;
}

async function main() {
  const client = new Client({ connectionString: process.env.POSTGRES_URL });
  await client.connect();

  const { rows } = await client.query('SELECT count(*)::int AS n FROM "User"');
  if (rows[0].n === 0) {
    const status = await createViaCredentials();
    console.log(`[seed-admin] no user existed; credentials sign-in returned ${status}`);
  } else {
    console.log(`[seed-admin] ${rows[0].n} user(s) already present`);
  }

  const hash = await bcrypt.hash(PASSWORD, SALT_ROUNDS);
  const updated = await client.query(
    'UPDATE "User" SET "passwordHash" = $1, "role" = \'admin\', "emailVerified" = COALESCE("emailVerified", now()), "updatedAt" = now() WHERE lower("email") = lower($2) RETURNING "id"',
    [hash, EMAIL],
  );

  if (updated.rowCount === 0) {
    console.error(`[seed-admin] FATAL: no account for ${EMAIL} after seeding`);
    process.exit(1);
  }
  console.log(`[seed-admin] administrator ${EMAIL} is present and the password matches ADMIN_PASSWORD`);

  await client.end();
}

main().catch((err) => {
  console.error('[seed-admin] FATAL:', err);
  process.exit(1);
});
