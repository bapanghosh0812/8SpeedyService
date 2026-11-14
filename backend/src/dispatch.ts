import { config } from './config';
import { pool, tx } from './db';
import { boundingBox, distanceMeters } from './geo';
import { ISSUE_LABELS, Issue, VEHICLE_LABELS, VehicleType } from './pricing';
import { pushToUser } from './push';
import { emitToUser } from './realtime';

const MAX_OFFERS_PER_WAVE = 5;

export interface OfferPayload {
  bookingId: string;
  code: string;
  vehicleType: string;
  issue: string;
  note: string | null;
  lat: number;
  lng: number;
  address: string | null;
  visitFeePaise: number;
  distanceMeters: number;
  expiresAt: string;
}

/**
 * Runs one dispatch step for a single `searching` booking inside a transaction with row lock.
 * Safe to call concurrently from multiple API instances because of `FOR UPDATE SKIP LOCKED`.
 */
export async function dispatchOneBooking(bookingId?: string): Promise<boolean> {
  const notifications: Array<{ partnerId: string; offer: OfferPayload }> = [];
  let expiredCustomerId: string | null = null;
  let expiredBookingId: string | null = null;

  const didWork = await tx(async (client) => {
    const pickSql = bookingId
      ? `SELECT * FROM bookings
          WHERE id = $1 AND status = 'searching'
          FOR UPDATE SKIP LOCKED`
      : `SELECT * FROM bookings
          WHERE status = 'searching' AND next_dispatch_at <= now()
          ORDER BY next_dispatch_at ASC
          LIMIT 1
          FOR UPDATE SKIP LOCKED`;

    const res = await client.query(pickSql, bookingId ? [bookingId] : []);
    const b = res.rows[0];
    if (!b) return false;

    // Expire any pending offers from earlier waves whose TTL has passed.
    await client.query(
      `UPDATE booking_offers
          SET status = 'expired'
        WHERE booking_id = $1 AND status = 'pending' AND expires_at <= now()`,
      [b.id],
    );

    const radii = config.DISPATCH_RADII_M;
    const wave: number = Number(b.dispatch_wave);

    if (wave >= radii.length) {
      // All waves exhausted without acceptance -> mark booking expired.
      await client.query(
        `UPDATE bookings
            SET status = 'expired',
                next_dispatch_at = NULL,
                updated_at = now()
          WHERE id = $1`,
        [b.id],
      );
      await client.query(
        `INSERT INTO booking_events (booking_id, type, data)
         VALUES ($1, 'expired', '{}'::jsonb)`,
        [b.id],
      );
      expiredCustomerId = b.customer_id;
      expiredBookingId = b.id;
      return true;
    }

    const radiusM = radii[wave]!;
    const box = boundingBox(Number(b.lat), Number(b.lng), radiusM);

    // Find online, approved partners who service this vehicle_type, have a recent location,
    // are not currently on a live job, and have not already been offered this booking.
    const candidatesRes = await client.query<{
      user_id: string;
      lat: number;
      lng: number;
    }>(
      `SELECT p.user_id, p.lat, p.lng
         FROM partners p
         JOIN users u ON u.id = p.user_id
        WHERE p.is_online = true
          AND p.status = 'approved'
          AND u.status = 'active'
          AND p.user_id <> $1
          AND $2 = ANY(p.vehicle_types)
          AND p.lat BETWEEN $3 AND $4
          AND p.lng BETWEEN $5 AND $6
          AND p.location_at >= now() - interval '15 minutes'
          AND NOT EXISTS (
            SELECT 1 FROM bookings live
             WHERE live.partner_id = p.user_id
               AND live.status IN ('accepted', 'arrived', 'in_progress')
          )
          AND NOT EXISTS (
            SELECT 1 FROM booking_offers bo
             WHERE bo.booking_id = $7 AND bo.partner_id = p.user_id
          )`,
      [b.customer_id, b.vehicle_type, box.minLat, box.maxLat, box.minLng, box.maxLng, b.id],
    );

    const within = candidatesRes.rows
      .map((c) => ({
        partnerId: c.user_id,
        distanceM: Math.round(distanceMeters(Number(b.lat), Number(b.lng), Number(c.lat), Number(c.lng))),
      }))
      .filter((c) => c.distanceM <= radiusM)
      .sort((a, z) => a.distanceM - z.distanceM)
      .slice(0, MAX_OFFERS_PER_WAVE);

    const ttlSec = config.OFFER_TTL_SECONDS;
    const expiresAt = new Date(Date.now() + ttlSec * 1000);

    for (const cand of within) {
      await client.query(
        `INSERT INTO booking_offers (booking_id, partner_id, wave, distance_m, status, expires_at)
         VALUES ($1, $2, $3, $4, 'pending', $5)
         ON CONFLICT (booking_id, partner_id) DO NOTHING`,
        [b.id, cand.partnerId, wave + 1, cand.distanceM, expiresAt.toISOString()],
      );
      notifications.push({
        partnerId: cand.partnerId,
        offer: {
          bookingId: b.id,
          code: b.code,
          vehicleType: b.vehicle_type,
          issue: b.issue,
          note: b.note,
          lat: Number(b.lat),
          lng: Number(b.lng),
          address: b.address,
          visitFeePaise: Number(b.visit_fee_paise),
          distanceMeters: cand.distanceM,
          expiresAt: expiresAt.toISOString(),
        },
      });
    }

    // If we found candidates in this wave, wait OFFER_TTL_SECONDS before escalating;
    // if zero candidates in this wave, try the next wider radius after 2 seconds.
    const waitSec = within.length > 0 ? ttlSec : 2;
    await client.query(
      `UPDATE bookings
          SET dispatch_wave = $2,
              next_dispatch_at = now() + ($3 || ' seconds')::interval,
              updated_at = now()
        WHERE id = $1`,
      [b.id, wave + 1, String(waitSec)],
    );

    await client.query(
      `INSERT INTO booking_events (booking_id, type, data)
       VALUES ($1, 'dispatch_wave', $2::jsonb)`,
      [b.id, JSON.stringify({ wave: wave + 1, radiusM, offered: within.length })],
    );

    return true;
  });

  if (expiredCustomerId && expiredBookingId) {
    emitToUser(expiredCustomerId, 'booking:update', { bookingId: expiredBookingId, status: 'expired' });
    void pushToUser(expiredCustomerId, 'customer', {
      title: 'No mechanic available nearby',
      body: 'All nearby mechanics are busy right now. Tap to try again.',
      data: { type: 'booking_expired', bookingId: expiredBookingId },
    });
  }

  for (const n of notifications) {
    emitToUser(n.partnerId, 'offer:new', n.offer);
    const vLabel = VEHICLE_LABELS[n.offer.vehicleType as VehicleType] ?? n.offer.vehicleType;
    const iLabel = ISSUE_LABELS[n.offer.issue as Issue] ?? n.offer.issue;
    void pushToUser(n.partnerId, 'partner', {
      title: `New ${vLabel} job • ₹${Math.round(n.offer.visitFeePaise / 100)}`,
      body: `${iLabel} • ${(n.offer.distanceMeters / 1000).toFixed(1)} km away`,
      data: { type: 'job_offer', bookingId: n.offer.bookingId },
      urgent: true,
    });
  }

  return didWork;
}

/** Processes all currently due `searching` bookings (up to `limit` per tick). */
export async function runDispatchTick(limit = 25): Promise<number> {
  let processed = 0;
  for (let i = 0; i < limit; i++) {
    const ok = await dispatchOneBooking();
    if (!ok) break;
    processed++;
  }
  return processed;
}

let timer: NodeJS.Timeout | null = null;

export function startDispatchWorker(intervalMs = 1500): void {
  if (timer) return;
  timer = setInterval(() => {
    void runDispatchTick().catch((err) => {
      console.error('[dispatch] tick error', (err as Error).message);
    });
  }, intervalMs);
  timer.unref();
}

export function stopDispatchWorker(): void {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}

export async function cleanupStaleOffers(): Promise<void> {
  await pool.query(
    `UPDATE booking_offers
        SET status = 'expired'
      WHERE status = 'pending' AND expires_at <= now()`,
  );
}
