import { buildApp } from './app';
import { config } from './config';
import { migrate, pool } from './db';
import { startDispatchWorker, stopDispatchWorker } from './dispatch';
import { closeRealtime, initRealtime } from './realtime';

async function main() {
  await migrate((msg) => console.log(msg));
  const app = await buildApp();
  await app.ready();
  initRealtime(app.server, app.log);

  if (config.DISPATCH_WORKER) {
    startDispatchWorker(1500);
  }

  await app.listen({ host: '0.0.0.0', port: config.PORT });

  const shutdown = async (signal: string) => {
    app.log.info({ signal }, 'shutting down');
    stopDispatchWorker();
    await closeRealtime();
    await app.close();
    await pool.end();
    process.exit(0);
  };

  process.on('SIGINT', () => void shutdown('SIGINT'));
  process.on('SIGTERM', () => void shutdown('SIGTERM'));
}

main().catch((err) => {
  console.error('[fatal]', err);
  process.exit(1);
});
