/**
 * Admin CLI utility for managing partners and admin privileges from the terminal:
 *   npm run admin -- list-pending
 *   npm run admin -- approve +919876543210
 *   npm run admin -- grant-admin +919876543210
 */
import { one, pool, query } from './db';
import { firebaseAuth } from './firebase';

async function main() {
  const [cmd, arg] = process.argv.slice(2);
  if (cmd === 'list-pending') {
    const rows = await query(
      `SELECT u.phone, u.name, p.shop_name, p.vehicle_types, p.status, p.created_at
         FROM partners p JOIN users u ON u.id = p.user_id
        WHERE p.status = 'pending'
        ORDER BY p.created_at ASC`,
    );
    console.table(rows);
  } else if (cmd === 'approve' && arg) {
    const u = await one<{ id: string }>(pool, 'SELECT id FROM users WHERE phone = $1', [arg]);
    if (!u) throw new Error(`No user with phone ${arg}`);
    await query(`UPDATE partners SET status = 'approved', updated_at = now() WHERE user_id = $1`, [u.id]);
    console.log(`Approved partner ${arg} (${u.id})`);
  } else if (cmd === 'grant-admin' && arg) {
    const u = await one<{ firebase_uid: string }>(pool, 'SELECT firebase_uid FROM users WHERE phone = $1', [arg]);
    if (!u) throw new Error(`No user with phone ${arg}`);
    await firebaseAuth.setCustomUserClaims(u.firebase_uid, { admin: true });
    console.log(`Granted admin claim to ${arg}`);
  } else {
    console.log('Usage:\n  npm run admin -- list-pending\n  npm run admin -- approve +91XXXXXXXXXX\n  npm run admin -- grant-admin +91XXXXXXXXXX');
  }
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
