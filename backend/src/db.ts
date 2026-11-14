import fs from 'node:fs';
import path from 'node:path';
import { Pool, PoolClient, QueryResultRow } from 'pg';
import { config } from './config';

export const pool = new Pool({
  connectionString: config.DATABASE_URL,
  max: config.DB_POOL_MAX,
  ssl: config.DB_SSL ? { rejectUnauthorized: true } : undefined,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  // Never let a single slow query hold a connection forever.
  statement_timeout: 10_000,
  application_name: '8speedy-api',
});

pool.on('error', (err) => {
  // Idle client errors (e.g. DB restart). The pool replaces the client automatically.
  console.error('[db] idle client error', err.message);
});

export type Db = Pick<PoolClient, 'query'>;

export async function query<T extends QueryResultRow = any>(text: string, params: unknown[] = []): Promise<T[]> {
  const res = await pool.query<T>(text, params);
  return res.rows;
}

export async function one<T extends QueryResultRow = any>(
  db: Db,
  text: string,
  params: unknown[] = [],
): Promise<T | undefined> {
  const res = await db.query<T>(text, params);
  return res.rows[0];
}

/** Runs fn inside a transaction. Rolls back on any thrown error. */
export async function tx<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
}

/** Applies every migrations/*.sql file not yet recorded, in filename order, each in its own transaction. */
export async function migrate(log: (msg: string) => void = console.log): Promise<void> {
  const dir = path.resolve(__dirname, '..', 'migrations');
  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  const client = await pool.connect();
  try {
    // Serialize concurrent migrators (e.g. several instances booting at once).
    await client.query('SELECT pg_advisory_lock(84210001)');
    await client.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         version TEXT PRIMARY KEY,
         applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
       )`,
    );
    const applied = new Set(
      (await client.query<{ version: string }>('SELECT version FROM schema_migrations')).rows.map((r) => r.version),
    );
    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = fs.readFileSync(path.join(dir, file), 'utf8');
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [file]);
        await client.query('COMMIT');
        log(`[migrate] applied ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        throw new Error(`Migration ${file} failed: ${(err as Error).message}`);
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock(84210001)').catch(() => undefined);
    client.release();
  }
}
