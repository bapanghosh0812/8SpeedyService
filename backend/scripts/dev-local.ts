/**
 * Local development server that automatically boots an embedded PostgreSQL 17 instance
 * in ./data/dev-pg, runs migrations, and starts the Fastify + Socket.IO API on port 8080.
 * For production (Cloud Run / Cloud SQL / Supabase / Neon), use `npm start`.
 */
import path from 'node:path';
import EmbeddedPostgres from 'embedded-postgres';

const PG_PORT = Number(process.env.DEV_PG_PORT || 54329);
const PG_DIR = path.resolve(__dirname, '..', 'data', 'dev-pg');

async function startLocal() {
  const pgServer = new EmbeddedPostgres({
    databaseDir: PG_DIR,
    user: 'postgres',
    password: 'password',
    port: PG_PORT,
    persistent: true,
  });

  try {
    await pgServer.initialise();
  } catch {
    // Already initialized on disk
  }
  await pgServer.start();

  process.env.DATABASE_URL =
    process.env.DATABASE_URL || `postgresql://postgres:password@127.0.0.1:${PG_PORT}/postgres`;
  process.env.FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'speedyservice-dev';
  process.env.FIREBASE_AUTH_EMULATOR_HOST =
    process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';

  await import('../src/server');

  const stop = async () => {
    await pgServer.stop().catch(() => undefined);
    process.exit(0);
  };
  process.on('SIGINT', () => void stop());
  process.on('SIGTERM', () => void stop());
}

startLocal().catch((err) => {
  console.error('[dev-local] failed:', err);
  process.exit(1);
});
