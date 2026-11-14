import crypto from 'node:crypto';
import { config } from './config';
import { Db, one, pool, tx } from './db';
import { dispatchOneBooking } from './dispatch';
import {
  badRequest,
  conflict,
  forbidden,
  isPgError,
  notFound,
  PG_UNIQUE_VIOLATION,
  tooMany,
} from './errors';
import { isInServiceArea } from './geo';
import {
  Issue,
  MAX_CHARGE_PAISE,
  MAX_TOTAL_EXTRA_PAISE,
  VehicleType,
  visitFeePaise,
} from './pricing';
import { pushToUser } from './push';
import { emitToUser } from './realtime';

const MAX_OTP_ATTEMPTS = 5;

function generateBookingCode(): string {
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  const bytes = crypto.randomBytes(6);
  let out = 'SP-';
  for (let i = 0; i < 6; i++) {
    out += alphabet[bytes[i]! % alphabet.length];
  }
  return out;
}

function generateFourDigitOtp(): string {
  return String(crypto.randomInt(1000, 10000));
}

function timingSafeEqualFourDigit(a: string, b: string): boolean {
  if (a.length !== 4 || b.length !== 4) return false;
  return crypto.timingSafeEqual(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
}

export interface BookingChargeView {
  id: string;
  description: string;
  amountPaise: number;
  status: 'pending' | 'approved' | 'rejected';
  createdAt: string;
}

export interface BookingView {
  id: string;
  code: string;
  status: 'searching' | 'accepted' | 'arrived' | 'in_progress' | 'completed' | 'cancelled' | 'expired';
  vehicleType: string;
  issue: string;
  note: string | null;
  vehicleNumber: string | null;
  lat: number;
  lng: number;
  address: string | null;
  visitFeePaise: number;
  extraPaise: number;
  totalPaise: number;
  paymentMethod: string | null;
  /** Included ONLY when viewer is the customer of this booking. Never sent to partners. */
  startOtp?: string;
  customer?: {
    id: string;
    name: string | null;
    phone: string;
  };
  partner?: {
    id: string;
    name: string | null;
    shopName: string;
    phone: string;
    upiId: string | null;
    lat: number | null;
    lng: number | null;
    rating: number | null;
    ratingCount: number;
  };
  charges: BookingChargeView[];
  rating: { stars: number; comment: string | null } | null;
  createdAt: string;
  acceptedAt: string | null;
  arrivedAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
}

/**
 * Loads a booking and formats it specifically for `viewerUserId`.
 * Enforces strict authorization: only the booking's customer, assigned partner, or an admin may view it.
 * Redacts `startOtp` for everyone except the customer.
 */
export async function getBookingForViewer(
  bookingId: string,
  viewerUserId: string,
  isAdmin = false,
  db: Db = pool,
): Promise<BookingView> {
  const row = await one<any>(
    db,
    `SELECT b.*,
            cu.name  AS customer_name,
            cu.phone AS customer_phone,
            pu.name  AS partner_name,
            pu.phone AS partner_phone,
            p.shop_name,
            p.upi_id,
            p.lat AS partner_lat,
            p.lng AS partner_lng,
            p.rating_sum,
            p.rating_count
       FROM bookings b
       JOIN users cu ON cu.id = b.customer_id
       LEFT JOIN partners p ON p.user_id = b.partner_id
       LEFT JOIN users pu ON pu.id = b.partner_id
      WHERE b.id = $1`,
    [bookingId],
  );
  if (!row) throw notFound('Booking not found');

  const isCustomer = row.customer_id === viewerUserId;
  const isAssignedPartner = row.partner_id === viewerUserId;
  if (!isCustomer && !isAssignedPartner && !isAdmin) {
    throw forbidden('FORBIDDEN', 'You do not have access to this booking');
  }

  const chargesRes = await db.query<any>(
    `SELECT id, description, amount_paise, status, created_at
       FROM booking_charges
      WHERE booking_id = $1
      ORDER BY created_at ASC`,
    [bookingId],
  );

  const ratingRow = await one<any>(
    db,
    `SELECT stars, comment FROM ratings WHERE booking_id = $1`,
    [bookingId],
  );

  const visitFee = Number(row.visit_fee_paise);
  const extra = Number(row.extra_paise);
  const view: BookingView = {
    id: row.id,
    code: row.code,
    status: row.status,
    vehicleType: row.vehicle_type,
    issue: row.issue,
    note: row.note,
    vehicleNumber: row.vehicle_number,
    lat: Number(row.lat),
    lng: Number(row.lng),
    address: row.address,
    visitFeePaise: visitFee,
    extraPaise: extra,
    totalPaise: visitFee + extra,
    paymentMethod: row.payment_method,
    charges: chargesRes.rows.map((c) => ({
      id: c.id,
      description: c.description,
      amountPaise: Number(c.amount_paise),
      status: c.status,
      createdAt: new Date(c.created_at).toISOString(),
    })),
    rating: ratingRow ? { stars: Number(ratingRow.stars), comment: ratingRow.comment } : null,
    createdAt: new Date(row.created_at).toISOString(),
    acceptedAt: row.accepted_at ? new Date(row.accepted_at).toISOString() : null,
    arrivedAt: row.arrived_at ? new Date(row.arrived_at).toISOString() : null,
    startedAt: row.started_at ? new Date(row.started_at).toISOString() : null,
    completedAt: row.completed_at ? new Date(row.completed_at).toISOString() : null,
  };

  if (isCustomer) {
    view.startOtp = row.start_otp;
  }

  if (isAssignedPartner || isAdmin) {
    view.customer = {
      id: row.customer_id,
      name: row.customer_name,
      phone: row.customer_phone,
    };
  }

  if (row.partner_id && (isCustomer || isAssignedPartner || isAdmin)) {
    const rCount = Number(row.rating_count ?? 0);
    const rSum = Number(row.rating_sum ?? 0);
    view.partner = {
      id: row.partner_id,
      name: row.partner_name,
      shopName: row.shop_name,
      phone: row.partner_phone,
      upiId: row.upi_id,
      lat: row.partner_lat !== null ? Number(row.partner_lat) : null,
      lng: row.partner_lng !== null ? Number(row.partner_lng) : null,
      rating: rCount > 0 ? Math.round((rSum / rCount) * 10) / 10 : null,
      ratingCount: rCount,
    };
  }

  return view;
}

export interface CreateBookingInput {
  customerId: string;
  vehicleType: VehicleType;
  issue: Issue;
  lat: number;
  lng: number;
  address?: string;
  note?: string;
  vehicleNumber?: string;
  idempotencyKey?: string;
}

export async function createBooking(input: CreateBookingInput): Promise<BookingView> {
  if (!isInServiceArea(input.lat, input.lng)) {
    throw badRequest('OUTSIDE_SERVICE_AREA', 'Location is outside the supported service area in India');
  }

  const bookingId = await tx(async (client) => {
    if (input.idempotencyKey) {
      const existing = await one<{ booking_id: string }>(
        client,
        `SELECT booking_id FROM idempotency_keys WHERE user_id = $1 AND key = $2`,
        [input.customerId, input.idempotencyKey],
      );
      if (existing) return existing.booking_id;
    }

    const fee = visitFeePaise(input.vehicleType);
    const otp = generateFourDigitOtp();
    const code = generateBookingCode();

    let createdId: string;
    try {
      const row = await one<{ id: string }>(
        client,
        `INSERT INTO bookings (
           code, customer_id, vehicle_type, issue, note, vehicle_number,
           lat, lng, address, status, visit_fee_paise, start_otp, next_dispatch_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'searching', $10, $11, now())
         RETURNING id`,
        [
          code,
          input.customerId,
          input.vehicleType,
          input.issue,
          input.note ?? null,
          input.vehicleNumber ?? null,
          input.lat,
          input.lng,
          input.address ?? null,
          fee,
          otp,
        ],
      );
      createdId = row!.id;
    } catch (err) {
      if (isPgError(err, PG_UNIQUE_VIOLATION, 'bookings_one_live_per_customer')) {
        throw conflict('ACTIVE_BOOKING_EXISTS', 'You already have an active booking');
      }
      throw err;
    }

    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id, data)
       VALUES ($1, 'created', $2, $3::jsonb)`,
      [createdId, input.customerId, JSON.stringify({ vehicleType: input.vehicleType, issue: input.issue })],
    );

    if (input.idempotencyKey) {
      await client.query(
        `INSERT INTO idempotency_keys (user_id, key, booking_id)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, key) DO NOTHING`,
        [input.customerId, input.idempotencyKey, createdId],
      );
    }

    return createdId;
  });

  // Immediately run Wave 1 dispatch so nearby mechanics get the offer within milliseconds.
  await dispatchOneBooking(bookingId);
  return getBookingForViewer(bookingId, input.customerId);
}

/**
 * Partner accepts an offer.
 * First-accept-wins is enforced atomically via row locks AND the partial unique index
 * `bookings_one_live_per_partner`.
 */
export async function acceptOffer(bookingId: string, partnerId: string): Promise<BookingView> {
  const { customerId, otherPartnerIds } = await tx(async (client) => {
    const partner = await one<{ status: string; is_online: boolean }>(
      client,
      `SELECT status, is_online FROM partners WHERE user_id = $1 FOR UPDATE`,
      [partnerId],
    );
    if (!partner || partner.status !== 'approved') {
      throw forbidden('PARTNER_NOT_APPROVED', 'Your partner account is not approved yet');
    }

    const booking = await one<any>(
      client,
      `SELECT id, customer_id, status FROM bookings WHERE id = $1 FOR UPDATE`,
      [bookingId],
    );
    if (!booking) throw notFound('Booking not found');
    if (booking.customer_id === partnerId) {
      throw forbidden('SELF_DEALING_FORBIDDEN', 'You cannot accept your own booking');
    }
    if (booking.status !== 'searching') {
      throw conflict('BOOKING_ALREADY_TAKEN', 'Another mechanic already accepted this job');
    }

    const offer = await one<{ status: string; expires_at: Date }>(
      client,
      `SELECT status, expires_at
         FROM booking_offers
        WHERE booking_id = $1 AND partner_id = $2
        FOR UPDATE`,
      [bookingId, partnerId],
    );
    if (!offer || offer.status !== 'pending' || new Date(offer.expires_at).getTime() <= Date.now()) {
      throw conflict('OFFER_EXPIRED', 'This job offer has expired');
    }

    try {
      await client.query(
        `UPDATE bookings
            SET partner_id = $2,
                status = 'accepted',
                accepted_at = now(),
                next_dispatch_at = NULL,
                updated_at = now()
          WHERE id = $1`,
        [bookingId, partnerId],
      );
    } catch (err) {
      if (isPgError(err, PG_UNIQUE_VIOLATION, 'bookings_one_live_per_partner')) {
        throw conflict('PARTNER_BUSY', 'You already have an active job');
      }
      throw err;
    }

    await client.query(
      `UPDATE booking_offers SET status = 'accepted' WHERE booking_id = $1 AND partner_id = $2`,
      [bookingId, partnerId],
    );

    const others = await client.query<{ partner_id: string }>(
      `UPDATE booking_offers
          SET status = 'lost'
        WHERE booking_id = $1 AND partner_id <> $2 AND status = 'pending'
      RETURNING partner_id`,
      [bookingId, partnerId],
    );

    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id, data)
       VALUES ($1, 'accepted', $2, '{}'::jsonb)`,
      [bookingId, partnerId],
    );

    return {
      customerId: booking.customer_id as string,
      otherPartnerIds: others.rows.map((r) => r.partner_id),
    };
  });

  const customerView = await getBookingForViewer(bookingId, customerId);
  emitToUser(customerId, 'booking:update', customerView);
  for (const otherId of otherPartnerIds) {
    emitToUser(otherId, 'offer:closed', { bookingId });
  }
  void pushToUser(customerId, 'customer', {
    title: 'Mechanic assigned!',
    body: `${customerView.partner?.shopName ?? 'Your mechanic'} is on the way.`,
    data: { type: 'booking_accepted', bookingId },
  });

  return getBookingForViewer(bookingId, partnerId);
}

export async function rejectOffer(bookingId: string, partnerId: string): Promise<void> {
  await pool.query(
    `UPDATE booking_offers
        SET status = 'rejected'
      WHERE booking_id = $1 AND partner_id = $2 AND status = 'pending'`,
    [bookingId, partnerId],
  );
}

export async function markArrived(bookingId: string, partnerId: string): Promise<BookingView> {
  const customerId = await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status FROM bookings WHERE id = $1 FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');
    if (b.partner_id !== partnerId) throw forbidden();
    if (b.status !== 'accepted') {
      throw conflict('INVALID_STATE', `Cannot mark arrived when booking is ${b.status}`);
    }
    await client.query(
      `UPDATE bookings SET status = 'arrived', arrived_at = now(), updated_at = now() WHERE id = $1`,
      [bookingId],
    );
    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id) VALUES ($1, 'arrived', $2)`,
      [bookingId, partnerId],
    );
    return b.customer_id as string;
  });

  const customerView = await getBookingForViewer(bookingId, customerId);
  emitToUser(customerId, 'booking:update', customerView);
  void pushToUser(customerId, 'customer', {
    title: 'Mechanic has arrived',
    body: `Share your 4-digit start code (${customerView.startOtp}) to begin repair.`,
    data: { type: 'booking_arrived', bookingId },
  });

  return getBookingForViewer(bookingId, partnerId);
}

export async function startWork(bookingId: string, partnerId: string, otp: string): Promise<BookingView> {
  const outcome = await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status, start_otp, otp_attempts
         FROM bookings
        WHERE id = $1
        FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');
    if (b.partner_id !== partnerId) throw forbidden();
    if (b.status !== 'arrived') {
      throw conflict('INVALID_STATE', `Cannot start work when booking is ${b.status}`);
    }
    if (Number(b.otp_attempts) >= MAX_OTP_ATTEMPTS) {
      throw tooMany('OTP_LOCKED', 'Too many wrong OTP attempts');
    }

    if (!timingSafeEqualFourDigit(otp, String(b.start_otp))) {
      const nextAttempts = Number(b.otp_attempts) + 1;
      await client.query(
        `UPDATE bookings SET otp_attempts = $2, updated_at = now() WHERE id = $1`,
        [bookingId, nextAttempts],
      );
      return { ok: false as const, remaining: MAX_OTP_ATTEMPTS - nextAttempts, customerId: b.customer_id as string };
    }

    await client.query(
      `UPDATE bookings SET status = 'in_progress', started_at = now(), updated_at = now() WHERE id = $1`,
      [bookingId],
    );
    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id) VALUES ($1, 'started', $2)`,
      [bookingId, partnerId],
    );
    return { ok: true as const, customerId: b.customer_id as string };
  });

  if (!outcome.ok) {
    if (outcome.remaining <= 0) {
      throw tooMany('OTP_LOCKED', 'Too many wrong OTP attempts');
    }
    throw badRequest('INVALID_OTP', `Wrong start code (${outcome.remaining} attempts left)`);
  }

  const customerView = await getBookingForViewer(bookingId, outcome.customerId);
  emitToUser(outcome.customerId, 'booking:update', customerView);
  return getBookingForViewer(bookingId, partnerId);
}

export async function addCharge(
  bookingId: string,
  partnerId: string,
  description: string,
  amountPaise: number,
): Promise<BookingView> {
  if (!Number.isInteger(amountPaise) || amountPaise <= 0 || amountPaise > MAX_CHARGE_PAISE) {
    throw badRequest('INVALID_AMOUNT', 'Charge amount is out of allowed range');
  }

  const customerId = await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status FROM bookings WHERE id = $1 FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');
    if (b.partner_id !== partnerId) throw forbidden();
    if (b.status !== 'in_progress') {
      throw conflict('INVALID_STATE', 'Extra charges can only be added while repair is in progress');
    }

    const sumRow = await one<{ total: string }>(
      client,
      `SELECT COALESCE(SUM(amount_paise), 0)::text AS total
         FROM booking_charges
        WHERE booking_id = $1 AND status IN ('pending', 'approved')`,
      [bookingId],
    );
    if (Number(sumRow?.total ?? 0) + amountPaise > MAX_TOTAL_EXTRA_PAISE) {
      throw badRequest('MAX_EXTRA_EXCEEDED', 'Total extra charges exceed maximum allowed');
    }

    await client.query(
      `INSERT INTO booking_charges (booking_id, description, amount_paise, status)
       VALUES ($1, $2, $3, 'pending')`,
      [bookingId, description.trim(), amountPaise],
    );
    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id, data)
       VALUES ($1, 'charge_added', $2, $3::jsonb)`,
      [bookingId, partnerId, JSON.stringify({ description: description.trim(), amountPaise })],
    );
    return b.customer_id as string;
  });

  const customerView = await getBookingForViewer(bookingId, customerId);
  emitToUser(customerId, 'booking:update', customerView);
  void pushToUser(customerId, 'customer', {
    title: 'Approve extra part / repair charge',
    body: `${description.trim()} • ₹${Math.round(amountPaise / 100)}`,
    data: { type: 'charge_added', bookingId },
  });

  return getBookingForViewer(bookingId, partnerId);
}

export async function decideCharge(
  bookingId: string,
  chargeId: string,
  customerId: string,
  decision: 'approved' | 'rejected',
): Promise<BookingView> {
  const partnerId = await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status FROM bookings WHERE id = $1 FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');
    if (b.customer_id !== customerId) throw forbidden();
    if (b.status !== 'in_progress') {
      throw conflict('INVALID_STATE', 'Charges can only be decided while repair is in progress');
    }

    const ch = await one<any>(
      client,
      `SELECT id, status FROM booking_charges WHERE id = $1 AND booking_id = $2 FOR UPDATE`,
      [chargeId, bookingId],
    );
    if (!ch) throw notFound('Charge not found');
    if (ch.status !== 'pending') {
      throw conflict('ALREADY_DECIDED', 'This charge was already decided');
    }

    await client.query(
      `UPDATE booking_charges SET status = $2, decided_at = now() WHERE id = $1`,
      [chargeId, decision],
    );

    const approvedSum = await one<{ total: string }>(
      client,
      `SELECT COALESCE(SUM(amount_paise), 0)::text AS total
         FROM booking_charges
        WHERE booking_id = $1 AND status = 'approved'`,
      [bookingId],
    );
    await client.query(
      `UPDATE bookings SET extra_paise = $2, updated_at = now() WHERE id = $1`,
      [bookingId, Number(approvedSum?.total ?? 0)],
    );
    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id, data)
       VALUES ($1, 'charge_decided', $2, $3::jsonb)`,
      [bookingId, customerId, JSON.stringify({ chargeId, decision })],
    );

    return b.partner_id as string;
  });

  const partnerView = await getBookingForViewer(bookingId, partnerId);
  emitToUser(partnerId, 'booking:update', partnerView);
  return getBookingForViewer(bookingId, customerId);
}

export async function completeBooking(
  bookingId: string,
  partnerId: string,
  paymentMethod: 'cash' | 'upi',
): Promise<BookingView> {
  const customerId = await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status, visit_fee_paise, extra_paise
         FROM bookings
        WHERE id = $1
        FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');
    if (b.partner_id !== partnerId) throw forbidden();
    if (b.status !== 'in_progress') {
      throw conflict('INVALID_STATE', `Cannot complete booking when status is ${b.status}`);
    }

    const pendingRow = await one<{ cnt: string }>(
      client,
      `SELECT COUNT(*)::text AS cnt FROM booking_charges WHERE booking_id = $1 AND status = 'pending'`,
      [bookingId],
    );
    if (Number(pendingRow?.cnt ?? 0) > 0) {
      throw conflict(
        'PENDING_CHARGES',
        'Ask the customer to approve or reject pending extra charges before completing',
      );
    }

    const totalPaise = Number(b.visit_fee_paise) + Number(b.extra_paise);
    const commissionPaise = Math.round((totalPaise * config.COMMISSION_BPS) / 10_000);

    await client.query(
      `UPDATE bookings
          SET status = 'completed',
              payment_method = $2,
              commission_paise = $3,
              completed_at = now(),
              updated_at = now()
        WHERE id = $1`,
      [bookingId, paymentMethod, commissionPaise],
    );

    await client.query(
      `INSERT INTO ledger_entries (partner_id, booking_id, type, amount_paise, note)
       VALUES ($1, $2, 'commission_due', $3, $4)`,
      [partnerId, bookingId, commissionPaise, `Commission on booking ${bookingId}`],
    );

    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id, data)
       VALUES ($1, 'completed', $2, $3::jsonb)`,
      [bookingId, partnerId, JSON.stringify({ paymentMethod, totalPaise, commissionPaise })],
    );

    return b.customer_id as string;
  });

  const customerView = await getBookingForViewer(bookingId, customerId);
  emitToUser(customerId, 'booking:update', customerView);
  void pushToUser(customerId, 'customer', {
    title: 'Job completed',
    body: `Total ₹${Math.round(customerView.totalPaise / 100)}. Tap to rate your mechanic.`,
    data: { type: 'booking_completed', bookingId },
  });

  return getBookingForViewer(bookingId, partnerId);
}

export async function cancelBooking(
  bookingId: string,
  actorId: string,
  reason?: string,
): Promise<BookingView> {
  const { notifyUserId, notifyRole } = await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status FROM bookings WHERE id = $1 FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');

    const isCustomer = b.customer_id === actorId;
    const isPartner = b.partner_id === actorId;
    if (!isCustomer && !isPartner) throw forbidden();

    // Once repair has started (OTP verified), cancellation is blocked to prevent fraud.
    if (!['searching', 'accepted', 'arrived'].includes(b.status)) {
      throw conflict('CANNOT_CANCEL', `Booking cannot be cancelled once status is ${b.status}`);
    }

    const cancelledBy = isCustomer ? 'customer' : 'partner';
    await client.query(
      `UPDATE bookings
          SET status = 'cancelled',
              cancelled_by = $2,
              cancel_reason = $3,
              next_dispatch_at = NULL,
              updated_at = now()
        WHERE id = $1`,
      [bookingId, cancelledBy, reason ?? null],
    );

    await client.query(
      `UPDATE booking_offers SET status = 'expired' WHERE booking_id = $1 AND status = 'pending'`,
      [bookingId],
    );

    await client.query(
      `INSERT INTO booking_events (booking_id, type, actor_id, data)
       VALUES ($1, 'cancelled', $2, $3::jsonb)`,
      [bookingId, actorId, JSON.stringify({ cancelledBy, reason: reason ?? null })],
    );

    return {
      notifyUserId: isCustomer ? (b.partner_id as string | null) : (b.customer_id as string),
      notifyRole: isCustomer ? ('partner' as const) : ('customer' as const),
    };
  });

  if (notifyUserId) {
    const otherView = await getBookingForViewer(bookingId, notifyUserId);
    emitToUser(notifyUserId, 'booking:update', otherView);
    void pushToUser(notifyUserId, notifyRole, {
      title: 'Booking cancelled',
      body: reason ? `Reason: ${reason}` : 'The booking was cancelled.',
      data: { type: 'booking_cancelled', bookingId },
    });
  }

  return getBookingForViewer(bookingId, actorId);
}

export async function rateBooking(
  bookingId: string,
  customerId: string,
  stars: number,
  comment?: string,
): Promise<BookingView> {
  await tx(async (client) => {
    const b = await one<any>(
      client,
      `SELECT customer_id, partner_id, status FROM bookings WHERE id = $1 FOR UPDATE`,
      [bookingId],
    );
    if (!b) throw notFound('Booking not found');
    if (b.customer_id !== customerId) throw forbidden();
    if (b.status !== 'completed') {
      throw conflict('INVALID_STATE', 'You can only rate a completed booking');
    }

    try {
      await client.query(
        `INSERT INTO ratings (booking_id, stars, comment) VALUES ($1, $2, $3)`,
        [bookingId, stars, comment ?? null],
      );
    } catch (err) {
      if (isPgError(err, PG_UNIQUE_VIOLATION)) {
        throw conflict('ALREADY_RATED', 'You have already rated this booking');
      }
      throw err;
    }

    if (b.partner_id) {
      await client.query(
        `UPDATE partners
            SET rating_sum = rating_sum + $2,
                rating_count = rating_count + 1,
                updated_at = now()
          WHERE user_id = $1`,
        [b.partner_id, stars],
      );
    }
  });

  return getBookingForViewer(bookingId, customerId);
}
