import { migrate, pool } from './db';

async function run() {
  await migrate((m) => console.log(m));
  await pool.end();
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
