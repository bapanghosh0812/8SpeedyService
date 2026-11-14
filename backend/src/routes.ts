import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate, invalidateUserCache, requireAdmin } from './auth';
import {
  acceptOffer,
  addCharge,
  cancelBooking,
  completeBooking,
  createBooking,
  decideCharge,
  getBookingForViewer,
  markArrived,
  rateBooking,
  rejectOffer,
  startWork,
} from './bookings';
import { one, pool, query } from './db';
import { badRequest, conflict, forbidden, notFound } from './errors';
import { distanceMeters, isInServiceArea, MAX_PLAUSIBLE_SPEED_MS } from './geo';
import { catalog, ISSUES, MAX_CHARGE_PAISE, VEHICLE_TYPES } from './pricing';
import { emitToUser } from './realtime';
import { sniffImage, storePrivateFile } from './storage';

const UuidParam = z.object({ id: z.string().uuid() }).strict();

const UpdateMeBody = z
  .object({
    name: z.string().trim().min(1).max(80),
  })
  .strict();

const DeviceTokenBody = z
  .object({
    token: z.string().trim().min(10).max(512),
    app: z.enum(['customer', 'partner']),
  })
  .strict();

const CreateBookingBody = z
  .object({
    vehicleType: z.enum(VEHICLE_TYPES),
    issue: z.enum(ISSUES),
    lat: z.number().finite(),
    lng: z.number().finite(),
    address: z.string().trim().max(240).optional(),
    note: z.string().trim().max(300).optional(),
    vehicleNumber: z.string().trim().max(20).optional(),
    idempotencyKey: z.string().trim().min(8).max(128).optional(),
  })
  .strict();

const CancelBody = z
  .object({
    reason: z.string().trim().max(200).optional(),
  })
  .strict();

const ChargeDecisionParams = z
  .object({
    id: z.string().uuid(),
    chargeId: z.string().uuid(),
  })
  .strict();

const ChargeDecisionBody = z
  .object({
    decision: z.enum(['approved', 'rejected']),
  })
  .strict();

const RatingBody = z
  .object({
    stars: z.number().int().min(1).max(5),
    comment: z.string().trim().max(400).optional(),
  })
  .strict();

const PartnerApplyBody = z
  .object({
    name: z.string().trim().min(2).max(80),
    shopName: z.string().trim().min(2).max(120),
    vehicleTypes: z.array(z.enum(VEHICLE_TYPES)).min(1).max(VEHICLE_TYPES.length),
    upiId: z
      .string()
      .trim()
      .max(80)
      .regex(/^[a-zA-Z0-9._-]{2,64}@[a-zA-Z0-9]{2,32}$/, 'Invalid UPI ID')
      .optional(),
  })
  .strict();

const AvailabilityBody = z
  .object({
    isOnline: z.boolean(),
    lat: z.number().finite().optional(),
    lng: z.number().finite().optional(),
  })
  .strict();

const LocationBody = z
  .object({
    lat: z.number().finite(),
    lng: z.number().finite(),
  })
  .strict();

const StartWorkBody = z
  .object({
    otp: z.string().regex(/^\d{4}$/, 'OTP must be 4 digits'),
  })
  .strict();

const AddChargeBody = z
  .object({
    description: z.string().trim().min(2).max(140),
    amountPaise: z.number().int().min(100).max(MAX_CHARGE_PAISE),
  })
  .strict();

const CompleteBody = z
  .object({
    paymentMethod: z.enum(['cash', 'upi']),
  })
  .strict();

function parse<T extends z.ZodTypeAny>(schema: T, value: unknown): z.infer<T> {
  const r = schema.safeParse(value);
  if (!r.success) {
    const first = r.error.issues[0];
    throw badRequest('VALIDATION_ERROR', `${first?.path.join('.') || 'body'}: ${first?.message || 'invalid'}`);
  }
  return r.data;
}

export async function registerRoutes(app: FastifyInstance): Promise<void> {
  app.get('/healthz', async () => {
    await pool.query('SELECT 1');
    return { status: 'ok' };
  });

  app.get('/v1/catalog', async () => catalog());

  // =========================================================================
  // AUTHENTICATED USER PROFILE & DEVICE TOKENS
  // =========================================================================

  app.get('/v1/me', { preHandler: authenticate }, async (req) => {
    const partner = await one<any>(
      pool,
      `SELECT shop_name, vehicle_types, upi_id, status, is_online, lat, lng, rating_sum, rating_count
         FROM partners
        WHERE user_id = $1`,
      [req.user.id],
    );
    return {
      id: req.user.id,
      phone: req.user.phone,
      name: req.user.name,
      isAdmin: req.user.isAdmin,
      partner: partner
        ? {
            shopName: partner.shop_name,
            vehicleTypes: partner.vehicle_types,
            upiId: partner.upi_id,
            status: partner.status,
            isOnline: partner.is_online,
            lat: partner.lat !== null ? Number(partner.lat) : null,
            lng: partner.lng !== null ? Number(partner.lng) : null,
            rating:
              Number(partner.rating_count) > 0
                ? Math.round((Number(partner.rating_sum) / Number(partner.rating_count)) * 10) / 10
                : null,
            ratingCount: Number(partner.rating_count),
          }
        : null,
    };
  });

  app.patch('/v1/me', { preHandler: authenticate }, async (req) => {
    const body = parse(UpdateMeBody, req.body);
    await query('UPDATE users SET name = $2, updated_at = now() WHERE id = $1', [req.user.id, body.name]);
    invalidateUserCache(req.user.firebaseUid);
    return { id: req.user.id, phone: req.user.phone, name: body.name };
  });

  app.post('/v1/me/device-token', { preHandler: authenticate }, async (req) => {
    const body = parse(DeviceTokenBody, req.body);
    await query(
      `INSERT INTO device_tokens (token, user_id, app, updated_at)
       VALUES ($1, $2, $3, now())
       ON CONFLICT (token) DO UPDATE
         SET user_id = EXCLUDED.user_id,
             app = EXCLUDED.app,
             updated_at = now()`,
      [body.token, req.user.id, body.app],
    );
    return { ok: true };
  });

  // =========================================================================
  // CUSTOMER BOOKING ROUTES
  // =========================================================================

  app.post(
    '/v1/bookings',
    {
      preHandler: authenticate,
      config: { rateLimit: { max: 15, timeWindow: '1 minute' } },
    },
    async (req, reply) => {
      const body = parse(CreateBookingBody, req.body);
      const headerKey = req.headers['idempotency-key'];
      const idempotencyKey =
        typeof headerKey === 'string' && headerKey.trim().length >= 8
          ? headerKey.trim().slice(0, 128)
          : body.idempotencyKey;

      const view = await createBooking({
        customerId: req.user.id,
        vehicleType: body.vehicleType,
        issue: body.issue,
        lat: body.lat,
        lng: body.lng,
        address: body.address,
        note: body.note,
        vehicleNumber: body.vehicleNumber,
        idempotencyKey,
      });
      return reply.code(201).send(view);
    },
  );

  app.get('/v1/bookings/active', { preHandler: authenticate }, async (req) => {
    const row = await one<{ id: string }>(
      pool,
      `SELECT id FROM bookings
        WHERE customer_id = $1 AND status IN ('searching', 'accepted', 'arrived', 'in_progress')
        ORDER BY created_at DESC LIMIT 1`,
      [req.user.id],
    );
    if (!row) return { booking: null };
    return { booking: await getBookingForViewer(row.id, req.user.id) };
  });

  app.get('/v1/bookings', { preHandler: authenticate }, async (req) => {
    const rows = await query<{ id: string }>(
      `SELECT id FROM bookings WHERE customer_id = $1 ORDER BY created_at DESC LIMIT 30`,
      [req.user.id],
    );
    const items = await Promise.all(rows.map((r) => getBookingForViewer(r.id, req.user.id)));
    return { bookings: items };
  });

  app.get('/v1/bookings/:id', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    return getBookingForViewer(id, req.user.id, req.user.isAdmin);
  });

  app.post('/v1/bookings/:id/cancel', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    const body = parse(CancelBody, req.body ?? {});
    return cancelBooking(id, req.user.id, body.reason);
  });

  app.post('/v1/bookings/:id/charges/:chargeId/decision', { preHandler: authenticate }, async (req) => {
    const { id, chargeId } = parse(ChargeDecisionParams, req.params);
    const body = parse(ChargeDecisionBody, req.body);
    return decideCharge(id, chargeId, req.user.id, body.decision);
  });

  app.post('/v1/bookings/:id/rating', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    const body = parse(RatingBody, req.body);
    return rateBooking(id, req.user.id, body.stars, body.comment);
  });

  // =========================================================================
  // PARTNER (MECHANIC) ROUTES
  // =========================================================================

  app.get('/v1/partner/me', { preHandler: authenticate }, async (req) => {
    const p = await one<any>(
      pool,
      `SELECT p.*, u.name, u.phone
         FROM partners p
         JOIN users u ON u.id = p.user_id
        WHERE p.user_id = $1`,
      [req.user.id],
    );
    if (!p) return { partner: null, activeBooking: null };

    const docs = await query<{ kind: string; created_at: Date }>(
      `SELECT kind, created_at FROM partner_documents WHERE partner_id = $1`,
      [req.user.id],
    );

    const activeRow = await one<{ id: string }>(
      pool,
      `SELECT id FROM bookings
        WHERE partner_id = $1 AND status IN ('accepted', 'arrived', 'in_progress')
        LIMIT 1`,
      [req.user.id],
    );

    const rCount = Number(p.rating_count);
    const rSum = Number(p.rating_sum);
    return {
      partner: {
        userId: p.user_id,
        name: p.name,
        phone: p.phone,
        shopName: p.shop_name,
        vehicleTypes: p.vehicle_types,
        upiId: p.upi_id,
        status: p.status,
        isOnline: p.is_online,
        lat: p.lat !== null ? Number(p.lat) : null,
        lng: p.lng !== null ? Number(p.lng) : null,
        rating: rCount > 0 ? Math.round((rSum / rCount) * 10) / 10 : null,
        ratingCount: rCount,
        documentsUploaded: docs.map((d) => d.kind),
      },
      activeBooking: activeRow ? await getBookingForViewer(activeRow.id, req.user.id) : null,
    };
  });

  app.post('/v1/partner/apply', { preHandler: authenticate }, async (req) => {
    const body = parse(PartnerApplyBody, req.body);
    const uniqueTypes = Array.from(new Set(body.vehicleTypes));

    await query('UPDATE users SET name = $2, updated_at = now() WHERE id = $1', [req.user.id, body.name]);
    invalidateUserCache(req.user.firebaseUid);

    const existing = await one<{ status: string }>(
      pool,
      'SELECT status FROM partners WHERE user_id = $1',
      [req.user.id],
    );
    if (existing && existing.status === 'suspended') {
      throw forbidden('PARTNER_SUSPENDED', 'Your partner account is suspended');
    }

    const row = await one<any>(
      pool,
      `INSERT INTO partners (user_id, shop_name, vehicle_types, upi_id, status)
       VALUES ($1, $2, $3, $4, 'pending')
       ON CONFLICT (user_id) DO UPDATE
         SET shop_name = EXCLUDED.shop_name,
             vehicle_types = EXCLUDED.vehicle_types,
             upi_id = EXCLUDED.upi_id,
             status = CASE WHEN partners.status = 'rejected' THEN 'pending' ELSE partners.status END,
             updated_at = now()
       RETURNING user_id, shop_name, vehicle_types, upi_id, status, is_online`,
      [req.user.id, body.shopName, uniqueTypes, body.upiId ?? null],
    );

    return {
      userId: row.user_id,
      shopName: row.shop_name,
      vehicleTypes: row.vehicle_types,
      upiId: row.upi_id,
      status: row.status,
      isOnline: row.is_online,
    };
  });

  app.post('/v1/partner/documents/:kind', { preHandler: authenticate }, async (req) => {
    const kindParsed = z
      .object({ kind: z.enum(['id_proof', 'selfie', 'shop_photo']) })
      .strict()
      .safeParse(req.params);
    if (!kindParsed.success) throw badRequest('INVALID_DOCUMENT_KIND', 'Invalid document type');
    const { kind } = kindParsed.data;

    const partner = await one<{ user_id: string }>(
      pool,
      'SELECT user_id FROM partners WHERE user_id = $1',
      [req.user.id],
    );
    if (!partner) throw badRequest('APPLY_FIRST', 'Submit partner application before uploading documents');

    const file = await req.file();
    if (!file) throw badRequest('FILE_REQUIRED', 'Image file is required');
    const buf = await file.toBuffer();
    if (file.file.truncated) {
      throw badRequest('FILE_TOO_LARGE', 'Image exceeds maximum allowed size (5 MB)');
    }
    const contentType = sniffImage(buf);
    if (!contentType) {
      throw badRequest('INVALID_IMAGE', 'Only JPEG, PNG or WebP images are accepted');
    }

    const ext = contentType === 'image/jpeg' ? 'jpg' : contentType === 'image/png' ? 'png' : 'webp';
    const objectPath = `kyc/${req.user.id}/${kind}-${Date.now()}.${ext}`;
    await storePrivateFile(objectPath, buf, contentType);

    await query(
      `INSERT INTO partner_documents (partner_id, kind, storage_path, content_type, size_bytes)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (partner_id, kind) DO UPDATE
         SET storage_path = EXCLUDED.storage_path,
             content_type = EXCLUDED.content_type,
             size_bytes = EXCLUDED.size_bytes,
             created_at = now()`,
      [req.user.id, kind, objectPath, contentType, buf.length],
    );

    return { kind, contentType, sizeBytes: buf.length };
  });

  app.post('/v1/partner/availability', { preHandler: authenticate }, async (req) => {
    const body = parse(AvailabilityBody, req.body);
    const partner = await one<any>(
      pool,
      'SELECT status, lat, lng FROM partners WHERE user_id = $1',
      [req.user.id],
    );
    if (!partner) throw forbidden('NOT_A_PARTNER', 'Partner application not found');
    if (partner.status !== 'approved') {
      throw forbidden('PARTNER_NOT_APPROVED', `Partner status is ${partner.status}`);
    }

    const lat = body.lat ?? (partner.lat !== null ? Number(partner.lat) : null);
    const lng = body.lng ?? (partner.lng !== null ? Number(partner.lng) : null);

    if (body.isOnline) {
      if (lat === null || lng === null) {
        throw badRequest('LOCATION_REQUIRED', 'GPS location is required to go online');
      }
      if (!isInServiceArea(lat, lng)) {
        throw badRequest('OUTSIDE_SERVICE_AREA', 'Location is outside the supported service area in India');
      }
      await query(
        `UPDATE partners
            SET is_online = true,
                lat = $2,
                lng = $3,
                location_at = now(),
                updated_at = now()
          WHERE user_id = $1`,
        [req.user.id, lat, lng],
      );
    } else {
      await query(
        `UPDATE partners SET is_online = false, updated_at = now() WHERE user_id = $1`,
        [req.user.id],
      );
    }

    return { isOnline: body.isOnline, lat, lng };
  });

  app.post(
    '/v1/partner/location',
    {
      preHandler: authenticate,
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (req) => {
      const body = parse(LocationBody, req.body);
      if (!isInServiceArea(body.lat, body.lng)) {
        throw badRequest('OUTSIDE_SERVICE_AREA', 'Location is outside India service area');
      }

      const prev = await one<{ status: string; lat: number | null; lng: number | null; location_at: Date | null }>(
        pool,
        'SELECT status, lat, lng, location_at FROM partners WHERE user_id = $1',
        [req.user.id],
      );
      if (!prev || prev.status !== 'approved') {
        throw forbidden('PARTNER_NOT_APPROVED', 'Partner account is not approved');
      }

      // Anti-teleportation velocity check if the previous fix was within the last 2 minutes.
      if (prev.lat !== null && prev.lng !== null && prev.location_at) {
        const elapsedSec = Math.max(1, (Date.now() - new Date(prev.location_at).getTime()) / 1000);
        if (elapsedSec < 120) {
          const distM = distanceMeters(Number(prev.lat), Number(prev.lng), body.lat, body.lng);
          if (distM > 500 && distM / elapsedSec > MAX_PLAUSIBLE_SPEED_MS) {
            throw badRequest('IMPLAUSIBLE_LOCATION_JUMP', 'GPS jump exceeds plausible ground speed');
          }
        }
      }

      await query(
        `UPDATE partners
            SET lat = $2,
                lng = $3,
                location_at = now(),
                updated_at = now()
          WHERE user_id = $1`,
        [req.user.id, body.lat, body.lng],
      );

      // If partner is on an active job, relay live coordinates to that booking's customer.
      const active = await one<{ id: string; customer_id: string }>(
        pool,
        `SELECT id, customer_id FROM bookings
          WHERE partner_id = $1 AND status IN ('accepted', 'arrived', 'in_progress')
          LIMIT 1`,
        [req.user.id],
      );
      if (active) {
        emitToUser(active.customer_id, 'partner:location', {
          bookingId: active.id,
          lat: body.lat,
          lng: body.lng,
          at: new Date().toISOString(),
        });
      }

      return { ok: true };
    },
  );

  app.get('/v1/partner/offers', { preHandler: authenticate }, async (req) => {
    const rows = await query<any>(
      `SELECT bo.booking_id,
              bo.distance_m,
              bo.expires_at,
              b.code,
              b.vehicle_type,
              b.issue,
              b.note,
              b.lat,
              b.lng,
              b.address,
              b.visit_fee_paise
         FROM booking_offers bo
         JOIN bookings b ON b.id = bo.booking_id
        WHERE bo.partner_id = $1
          AND bo.status = 'pending'
          AND bo.expires_at > now()
          AND b.status = 'searching'
        ORDER BY bo.created_at DESC`,
      [req.user.id],
    );

    return {
      offers: rows.map((r) => ({
        bookingId: r.booking_id,
        code: r.code,
        vehicleType: r.vehicle_type,
        issue: r.issue,
        note: r.note,
        lat: Number(r.lat),
        lng: Number(r.lng),
        address: r.address,
        visitFeePaise: Number(r.visit_fee_paise),
        distanceMeters: Number(r.distance_m),
        expiresAt: new Date(r.expires_at).toISOString(),
      })),
    };
  });

  app.post('/v1/partner/bookings/:id/accept', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    return acceptOffer(id, req.user.id);
  });

  app.post('/v1/partner/bookings/:id/reject', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    await rejectOffer(id, req.user.id);
    return { ok: true };
  });

  app.post('/v1/partner/bookings/:id/arrive', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    return markArrived(id, req.user.id);
  });

  app.post('/v1/partner/bookings/:id/start', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    const body = parse(StartWorkBody, req.body);
    return startWork(id, req.user.id, body.otp);
  });

  app.post('/v1/partner/bookings/:id/charges', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    const body = parse(AddChargeBody, req.body);
    return addCharge(id, req.user.id, body.description, body.amountPaise);
  });

  app.post('/v1/partner/bookings/:id/complete', { preHandler: authenticate }, async (req) => {
    const { id } = parse(UuidParam, req.params);
    const body = parse(CompleteBody, req.body);
    return completeBooking(id, req.user.id, body.paymentMethod);
  });

  app.get('/v1/partner/earnings', { preHandler: authenticate }, async (req) => {
    const summary = await one<any>(
      pool,
      `SELECT COUNT(*)::int AS completed_jobs,
              COALESCE(SUM(visit_fee_paise + extra_paise), 0)::bigint AS gross_paise,
              COALESCE(SUM(commission_paise), 0)::bigint AS commission_paise
         FROM bookings
        WHERE partner_id = $1 AND status = 'completed'`,
      [req.user.id],
    );

    const ledgerBalance = await one<{ due_paise: string }>(
      pool,
      `SELECT COALESCE(SUM(
         CASE
           WHEN type = 'commission_due' THEN amount_paise
           WHEN type = 'commission_paid' THEN -amount_paise
           ELSE amount_paise
         END
       ), 0)::text AS due_paise
       FROM ledger_entries
       WHERE partner_id = $1`,
      [req.user.id],
    );

    const recentJobs = await query<any>(
      `SELECT id, code, vehicle_type, issue, visit_fee_paise, extra_paise, commission_paise, payment_method, completed_at
         FROM bookings
        WHERE partner_id = $1 AND status = 'completed'
        ORDER BY completed_at DESC
        LIMIT 25`,
      [req.user.id],
    );

    const grossPaise = Number(summary?.gross_paise ?? 0);
    const commissionPaise = Number(summary?.commission_paise ?? 0);
    return {
      completedJobs: Number(summary?.completed_jobs ?? 0),
      grossPaise,
      commissionPaise,
      netEarningsPaise: grossPaise - commissionPaise,
      commissionBalanceDuePaise: Number(ledgerBalance?.due_paise ?? 0),
      recentJobs: recentJobs.map((j) => ({
        id: j.id,
        code: j.code,
        vehicleType: j.vehicle_type,
        issue: j.issue,
        totalPaise: Number(j.visit_fee_paise) + Number(j.extra_paise),
        commissionPaise: Number(j.commission_paise ?? 0),
        netPaise: Number(j.visit_fee_paise) + Number(j.extra_paise) - Number(j.commission_paise ?? 0),
        paymentMethod: j.payment_method,
        completedAt: new Date(j.completed_at).toISOString(),
      })),
    };
  });

  // =========================================================================
  // ADMIN ROUTES (REQUIRE FIREBASE CUSTOM CLAIM admin = true)
  // =========================================================================

  app.get('/v1/admin/partners', { preHandler: requireAdmin }, async (req) => {
    const q = z
      .object({ status: z.enum(['pending', 'approved', 'rejected', 'suspended']).optional() })
      .safeParse(req.query);
    const statusFilter = q.success ? q.data.status : undefined;

    const rows = await query<any>(
      `SELECT p.user_id, u.phone, u.name, p.shop_name, p.vehicle_types, p.upi_id, p.status, p.is_online, p.created_at
         FROM partners p
         JOIN users u ON u.id = p.user_id
        WHERE ($1::text IS NULL OR p.status = $1)
        ORDER BY p.created_at DESC
        LIMIT 100`,
      [statusFilter ?? null],
    );
    return { partners: rows };
  });

  app.post('/v1/admin/partners/:userId/decision', { preHandler: requireAdmin }, async (req) => {
    const { userId } = parse(z.object({ userId: z.string().uuid() }).strict(), req.params);
    const body = parse(
      z.object({ status: z.enum(['approved', 'rejected', 'suspended']) }).strict(),
      req.body,
    );
    const row = await one<{ user_id: string; status: string }>(
      pool,
      `UPDATE partners
          SET status = $2,
              is_online = CASE WHEN $2 = 'approved' THEN is_online ELSE false END,
              updated_at = now()
        WHERE user_id = $1
      RETURNING user_id, status`,
      [userId, body.status],
    );
    if (!row) throw notFound('Partner not found');
    return { userId: row.user_id, status: row.status };
  });

  app.post('/v1/admin/partners/:userId/payment', { preHandler: requireAdmin }, async (req) => {
    const { userId } = parse(z.object({ userId: z.string().uuid() }).strict(), req.params);
    const body = parse(
      z
        .object({
          amountPaise: z.number().int().positive(),
          note: z.string().trim().max(200).optional(),
        })
        .strict(),
      req.body,
    );
    const p = await one<{ user_id: string }>(pool, 'SELECT user_id FROM partners WHERE user_id = $1', [userId]);
    if (!p) throw notFound('Partner not found');

    await query(
      `INSERT INTO ledger_entries (partner_id, type, amount_paise, note)
       VALUES ($1, 'commission_paid', $2, $3)`,
      [userId, body.amountPaise, body.note ?? 'Commission settlement received'],
    );
    return { ok: true };
  });

  // Catch any unknown route with a clean 404 JSON response.
  app.setNotFoundHandler((_req, reply) => {
    void reply.code(404).send({ error: 'NOT_FOUND', message: 'Route not found' });
  });

  // Ensure internal error details or stack traces never leak to clients.
  app.setErrorHandler((err: any, req, reply) => {
    if (typeof err?.status === 'number' && typeof err?.code === 'string') {
      return reply.code(err.status).send({ error: err.code, message: err.message });
    }
    if (err?.statusCode === 429) {
      return reply.code(429).send({ error: 'RATE_LIMITED', message: 'Too many requests, please slow down' });
    }
    if (err?.statusCode === 413) {
      return reply.code(413).send({ error: 'PAYLOAD_TOO_LARGE', message: 'Request payload is too large' });
    }
    req.log.error({ err }, 'unhandled error');
    return reply.code(500).send({ error: 'INTERNAL_ERROR', message: 'Something went wrong' });
  });
}
