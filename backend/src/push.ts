import { query } from './db';
import { messaging } from './firebase';

export type AppKind = 'customer' | 'partner';

export interface PushMessage {
  title: string;
  body: string;
  /** All values must be strings (FCM data payload rule). */
  data: Record<string, string>;
  /** Job offers use a high-priority channel with a loud sound and short TTL. */
  urgent?: boolean;
}

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** Fire-and-forget push. Never throws: a failed push must not fail the API call that triggered it. */
export async function pushToUser(userId: string, app: AppKind, msg: PushMessage): Promise<void> {
  if (!messaging) return;
  try {
    const rows = await query<{ token: string }>(
      'SELECT token FROM device_tokens WHERE user_id = $1 AND app = $2 ORDER BY updated_at DESC LIMIT 5',
      [userId, app],
    );
    if (rows.length === 0) return;
    const tokens = rows.map((r) => r.token);
    const res = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: msg.title, body: msg.body },
      data: msg.data,
      android: {
        priority: 'high',
        ttl: msg.urgent ? 30_000 : 3_600_000,
        notification: {
          channelId: msg.urgent ? 'job_offers' : 'booking_updates',
          sound: msg.urgent ? 'job_offer' : 'default',
        },
      },
      apns: {
        headers: { 'apns-priority': '10' },
        payload: { aps: { sound: msg.urgent ? 'job_offer.caf' : 'default' } },
      },
    });
    const dead = res.responses
      .map((r, i) => (!r.success && r.error && INVALID_TOKEN_CODES.has(r.error.code) ? tokens[i] : null))
      .filter((t): t is string => t !== null);
    if (dead.length) await query('DELETE FROM device_tokens WHERE token = ANY($1)', [dead]);
  } catch (err) {
    console.error('[push] failed', (err as Error).message);
  }
}
