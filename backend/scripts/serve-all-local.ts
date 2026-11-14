import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import EmbeddedPostgres from 'embedded-postgres';

const PG_PORT = Number(process.env.DEV_PG_PORT || 54329);
const PG_DIR = path.resolve(__dirname, '..', 'data', 'dev-pg');
const CUSTOMER_WEB_DIR = path.resolve(__dirname, '..', '..', 'apps', 'customer', 'build', 'web');
const PARTNER_WEB_DIR = path.resolve(__dirname, '..', '..', 'apps', 'partner', 'build', 'web');

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

function startStaticAppServer(rootDir: string, port: number, label: string): http.Server {
  const server = http.createServer((req, res) => {
    const urlPath = (req.url || '/').split('?')[0];
    const relPath = urlPath === '/' ? 'index.html' : urlPath.replace(/^\/+/, '');
    const resolved = path.resolve(rootDir, relPath);

    // Prevent path traversal outside rootDir
    if (!resolved.startsWith(rootDir)) {
      res.writeHead(403);
      res.end('Forbidden');
      return;
    }

    let targetFile = resolved;
    if (!fs.existsSync(targetFile) || fs.statSync(targetFile).isDirectory()) {
      targetFile = path.join(rootDir, 'index.html');
    }

    if (!fs.existsSync(targetFile)) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    const ext = path.extname(targetFile).toLowerCase();
    res.setHeader('Content-Type', MIME_TYPES[ext] || 'application/octet-stream');
    fs.createReadStream(targetFile).pipe(res);
  });

  server.listen(port, '127.0.0.1', () => {
    console.log(`[${label}] Live at http://127.0.0.1:${port}`);
  });
  return server;
}

async function main() {
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
    // Already initialized
  }
  await pgServer.start();

  process.env.DATABASE_URL =
    process.env.DATABASE_URL || `postgresql://postgres:password@127.0.0.1:${PG_PORT}/postgres`;
  process.env.FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'speedyservice-dev';
  process.env.FIREBASE_AUTH_EMULATOR_HOST =
    process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
  process.env.CORS_ORIGINS =
    'http://127.0.0.1:5001,http://localhost:5001,http://127.0.0.1:5002,http://localhost:5002';

  await import('../src/server');

  startStaticAppServer(CUSTOMER_WEB_DIR, 5001, 'Customer App');
  startStaticAppServer(PARTNER_WEB_DIR, 5002, 'Partner App');

  const stop = async () => {
    await pgServer.stop().catch(() => undefined);
    process.exit(0);
  };
  process.on('SIGINT', () => void stop());
  process.on('SIGTERM', () => void stop());
}

main().catch((err) => {
  console.error('[serve-all-local] failed:', err);
  process.exit(1);
});
