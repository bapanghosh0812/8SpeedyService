import assert from 'node:assert/strict';
import path from 'node:path';
import fs from 'node:fs/promises';
import { after, before, describe, it } from 'node:test';
import EmbeddedPostgres from 'embedded-postgres';
import { io as ioClient } from 'socket.io-client';

const PG_PORT = 55432;
const PG_DIR = path.resolve(__dirname, '..', 'data', 'test-pg');
const UPLOAD_DIR = path.resolve(__dirname, '..', 'data', 'test-uploads');
const PROJECT_ID = 'speedyservice-test';

// Configure environment BEFORE importing application modules.
process.env.NODE_ENV = 'test';
process.env.PORT = '8080';
process.env.DATABASE_URL =
  process.env.TEST_DATABASE_URL || `postgresql://postgres:password@127.0.0.1:${PG_PORT}/postgres`;
process.env.FIREBASE_PROJECT_ID = PROJECT_ID;
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.LOCAL_UPLOAD_DIR = UPLOAD_DIR;
process.env.DISPATCH_WORKER = 'false';
process.env.OFFER_TTL_SECONDS = '20';
process.env.DISPATCH_RADII_M = '3000,6000';
process.env.LOG_LEVEL = 'error';

/**
 * Crafts an unsigned Firebase Auth Emulator JWT.
 * Note: firebase-admin ONLY accepts unsigned tokens when FIREBASE_AUTH_EMULATOR_HOST is set,
 * and config.ts refuses to boot in production if FIREBASE_AUTH_EMULATOR_HOST is set.
 */
function makeEmulatorToken(opts: {
  uid: string;
  phone?: string;
  provider?: string;
  aud?: string;
  iss?: string;
  expOffsetSec?: number;
  admin?: boolean;
}): string {
  const b64 = (obj: unknown) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'none', typ: 'JWT' };
  const payload: Record<string, unknown> = {
    iss: opts.iss ?? `https://securetoken.google.com/${PROJECT_ID}`,
    aud: opts.aud ?? PROJECT_ID,
    auth_time: now - 10,
    user_id: opts.uid,
    sub: opts.uid,
    iat: now - 10,
    exp: now + (opts.expOffsetSec ?? 3600),
    phone_number: opts.phone ?? '+919876543210',
    firebase: {
      identities: { phone: [opts.phone ?? '+919876543210'] },
      sign_in_provider: opts.provider ?? 'phone',
    },
  };
  if (opts.admin) payload.admin = true;
  return `${b64(header)}.${b64(payload)}.`;
}

describe('8SpeedyService Production Backend — Integration & Adversarial Security Suite', () => {
  let pgServer: EmbeddedPostgres;
  let baseUrl = '';
  let closeApp: () => Promise<void>;
  let poolRef: import('pg').Pool;
  let runDispatchTickRef: (limit?: number) => Promise<number>;

  const customerToken = makeEmulatorToken({ uid: 'uid_cust_1', phone: '+919811111111' });
  const partner1Token = makeEmulatorToken({ uid: 'uid_part_1', phone: '+919822222221' });
  const partner2Token = makeEmulatorToken({ uid: 'uid_part_2', phone: '+919822222222' });
  const strangerToken = makeEmulatorToken({ uid: 'uid_stranger', phone: '+919833333333' });
  const adminToken = makeEmulatorToken({ uid: 'uid_admin', phone: '+919899999999', admin: true });

  async function api(
    method: string,
    route: string,
    opts: { token?: string; body?: unknown; headers?: Record<string, string> } = {},
  ): Promise<{ status: number; data: any }> {
    const headers: Record<string, string> = { ...(opts.headers ?? {}) };
    if (opts.token) headers.authorization = `Bearer ${opts.token}`;
    let payload: string | undefined;
    if (opts.body !== undefined) {
      headers['content-type'] = 'application/json';
      payload = JSON.stringify(opts.body);
    }
    const res = await fetch(`${baseUrl}${route}`, { method, headers, body: payload });
    const data = await res.json().catch(() => ({}));
    return { status: res.status, data };
  }

  before(async () => {
    await fs.rm(PG_DIR, { recursive: true, force: true });
    await fs.rm(UPLOAD_DIR, { recursive: true, force: true });

    if (!process.env.TEST_DATABASE_URL) {
      pgServer = new EmbeddedPostgres({
        databaseDir: PG_DIR,
        user: 'postgres',
        password: 'password',
        port: PG_PORT,
        persistent: false,
        onLog: () => undefined,
        onError: () => undefined,
      });
      await pgServer.initialise();
      await pgServer.start();
    }

    const { migrate, pool } = await import('../src/db');
    const { buildApp } = await import('../src/app');
    const { initRealtime, closeRealtime } = await import('../src/realtime');
    const { runDispatchTick } = await import('../src/dispatch');

    poolRef = pool;
    runDispatchTickRef = runDispatchTick;

    await migrate(() => undefined);
    const app = await buildApp();
    await app.ready();
    initRealtime(app.server, app.log);
    const address = await app.listen({ host: '127.0.0.1', port: 0 });
    baseUrl = address;

    closeApp = async () => {
      await closeRealtime();
      await app.close();
      await pool.end();
    };
  });

  after(async () => {
    if (closeApp) await closeApp();
    if (pgServer) await pgServer.stop();
    await fs.rm(PG_DIR, { recursive: true, force: true }).catch(() => undefined);
    await fs.rm(UPLOAD_DIR, { recursive: true, force: true }).catch(() => undefined);
  });

  it('1. Healthz and catalog return server-authoritative prices in paise', async () => {
    const h = await api('GET', '/healthz');
    assert.equal(h.status, 200);
    assert.equal(h.data.status, 'ok');

    const cat = await api('GET', '/v1/catalog');
    assert.equal(cat.status, 200);
    assert.equal(cat.data.currency, 'INR');
    const car = cat.data.vehicles.find((v: any) => v.id === 'car');
    assert.equal(car.visitFeePaise, 24900);
  });

  it('2. Blocks missing, forged, expired, wrong-project, non-phone, non-Indian, and disabled tokens', async () => {
    assert.equal((await api('GET', '/v1/me')).status, 401);
    assert.equal((await api('GET', '/v1/me', { token: 'not-a-jwt' })).status, 401);

    const wrongAud = makeEmulatorToken({ uid: 'u1', aud: 'other-project' });
    assert.equal((await api('GET', '/v1/me', { token: wrongAud })).status, 401);

    const expired = makeEmulatorToken({ uid: 'u1', expOffsetSec: -60 });
    assert.equal((await api('GET', '/v1/me', { token: expired })).status, 401);

    const emailProvider = makeEmulatorToken({ uid: 'u1', provider: 'password' });
    assert.equal((await api('GET', '/v1/me', { token: emailProvider })).status, 401);

    const foreignPhone = makeEmulatorToken({ uid: 'u_us', phone: '+14155550199' });
    assert.equal((await api('GET', '/v1/me', { token: foreignPhone })).status, 401);

    // Block a user in DB and confirm immediate rejection after cache invalidation.
    const blockedToken = makeEmulatorToken({ uid: 'uid_blocked', phone: '+919844444444' });
    assert.equal((await api('GET', '/v1/me', { token: blockedToken })).status, 200);
    await poolRef.query(`UPDATE users SET status = 'blocked' WHERE firebase_uid = 'uid_blocked'`);
    const { invalidateUserCache } = await import('../src/auth');
    invalidateUserCache('uid_blocked');
    const resBlocked = await api('GET', '/v1/me', { token: blockedToken });
    assert.equal(resBlocked.status, 403);
    assert.equal(resBlocked.data.error, 'ACCOUNT_DISABLED');
  });

  it('3. Rejects unknown extra JSON fields (price tampering / mass assignment) & SQL injection payloads', async () => {
    // Attacker tries to pass visitFeePaise: 100 or status: 'completed' on booking creation
    const tampered = await api('POST', '/v1/bookings', {
      token: customerToken,
      body: {
        vehicleType: 'car',
        issue: 'battery',
        lat: 18.5204,
        lng: 73.8567,
        visitFeePaise: 100,
      },
    });
    assert.equal(tampered.status, 400);
    assert.equal(tampered.data.error, 'VALIDATION_ERROR');

    // SQL injection payload in user name is stored literally without breaking table
    const sqliName = `Aarav'); DROP TABLE users;--`;
    const patchRes = await api('PATCH', '/v1/me', {
      token: customerToken,
      body: { name: sqliName },
    });
    assert.equal(patchRes.status, 200);
    assert.equal(patchRes.data.name, sqliName);
  });

  it('4. Enforces Partner KYC onboarding, magic-byte image sniffing, admin-only approval & GPS velocity guard', async () => {
    // Partner 1 and Partner 2 submit applications
    const apply1 = await api('POST', '/v1/partner/apply', {
      token: partner1Token,
      body: {
        name: 'Rajesh Mechanic',
        shopName: 'Vishwakarma Auto Works',
        vehicleTypes: ['bike', 'scooter', 'car'],
        upiId: 'rajesh@ybl',
      },
    });
    assert.equal(apply1.status, 200);
    assert.equal(apply1.data.status, 'pending');

    const apply2 = await api('POST', '/v1/partner/apply', {
      token: partner2Token,
      body: {
        name: 'Imran Mechanic',
        shopName: 'Highway Rescue Garage',
        vehicleTypes: ['bike', 'scooter', 'car'],
        upiId: 'imran@okaxis',
      },
    });
    assert.equal(apply2.status, 200);

    // Pending partner cannot go online before admin approval
    const prematureOnline = await api('POST', '/v1/partner/availability', {
      token: partner1Token,
      body: { isOnline: true, lat: 18.521, lng: 73.857 },
    });
    assert.equal(prematureOnline.status, 403);
    assert.equal(prematureOnline.data.error, 'PARTNER_NOT_APPROVED');

    // Fake KYC upload (plain text disguised as image/jpeg) must be rejected by magic-byte sniffer
    const fakeForm = new FormData();
    fakeForm.append('file', new Blob([Buffer.from('<!doctype html><script>alert(1)</script>')], { type: 'image/jpeg' }), 'id.jpg');
    const fakeUpload = await fetch(`${baseUrl}/v1/partner/documents/id_proof`, {
      method: 'POST',
      headers: { authorization: `Bearer ${partner1Token}` },
      body: fakeForm,
    });
    assert.equal(fakeUpload.status, 400);
    const fakeData: any = await fakeUpload.json();
    assert.equal(fakeData.error, 'INVALID_IMAGE');

    // Valid PNG magic bytes succeed
    const pngBytes = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    ]);
    const validForm = new FormData();
    validForm.append('file', new Blob([pngBytes], { type: 'image/png' }), 'id.png');
    const validUpload = await fetch(`${baseUrl}/v1/partner/documents/id_proof`, {
      method: 'POST',
      headers: { authorization: `Bearer ${partner1Token}` },
      body: validForm,
    });
    assert.equal(validUpload.status, 200);

    // Non-admin cannot approve a partner
    const p1Me = await api('GET', '/v1/partner/me', { token: partner1Token });
    const p2Me = await api('GET', '/v1/partner/me', { token: partner2Token });
    const p1Id = p1Me.data.partner.userId;
    const p2Id = p2Me.data.partner.userId;

    const nonAdminApprove = await api('POST', `/v1/admin/partners/${p1Id}/decision`, {
      token: customerToken,
      body: { status: 'approved' },
    });
    assert.equal(nonAdminApprove.status, 403);

    // Admin approves both Partner 1 and Partner 2
    assert.equal(
      (await api('POST', `/v1/admin/partners/${p1Id}/decision`, { token: adminToken, body: { status: 'approved' } })).status,
      200,
    );
    assert.equal(
      (await api('POST', `/v1/admin/partners/${p2Id}/decision`, { token: adminToken, body: { status: 'approved' } })).status,
      200,
    );

    // Both partners go online in Pune
    assert.equal(
      (
        await api('POST', '/v1/partner/availability', {
          token: partner1Token,
          body: { isOnline: true, lat: 18.521, lng: 73.857 },
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await api('POST', '/v1/partner/availability', {
          token: partner2Token,
          body: { isOnline: true, lat: 18.522, lng: 73.858 },
        })
      ).status,
      200,
    );

    // GPS teleportation attack (jumping from Pune to Mumbai 120 km away within 1 second) is blocked
    const teleport = await api('POST', '/v1/partner/location', {
      token: partner1Token,
      body: { lat: 19.076, lng: 72.8777 },
    });
    assert.equal(teleport.status, 400);
    assert.equal(teleport.data.error, 'IMPLAUSIBLE_LOCATION_JUMP');
  });

  it('5. Full Rapido-style booking flow: Idempotency, Concurrent Race Lock, Redacted OTP, Extra Charges & Immutable Ledger', async () => {
    // Connect realtime WebSocket as Customer
    const socket = ioClient(baseUrl, {
      transports: ['websocket'],
      auth: { token: customerToken },
    });
    await new Promise<void>((resolve, reject) => {
      socket.on('connect', () => resolve());
      socket.on('connect_error', (err) => reject(err));
    });

    const eventsReceived: string[] = [];
    socket.on('booking:update', (payload: any) => {
      eventsReceived.push(payload.status);
    });

    // Customer creates booking with Idempotency-Key
    const create1 = await api('POST', '/v1/bookings', {
      token: customerToken,
      headers: { 'idempotency-key': 'idem-key-booking-001' },
      body: {
        vehicleType: 'car',
        issue: 'battery',
        lat: 18.5204,
        lng: 73.8567,
        address: 'FC Road, Pune',
        vehicleNumber: 'MH12AB1234',
      },
    });
    assert.equal(create1.status, 201);
    const bookingId = create1.data.id;
    const customerOtp = create1.data.startOtp;
    assert.equal(create1.data.visitFeePaise, 24900);
    assert.match(customerOtp, /^\d{4}$/);

    // Repeating with the same Idempotency-Key returns the exact same booking
    const createRetry = await api('POST', '/v1/bookings', {
      token: customerToken,
      headers: { 'idempotency-key': 'idem-key-booking-001' },
      body: {
        vehicleType: 'car',
        issue: 'battery',
        lat: 18.5204,
        lng: 73.8567,
      },
    });
    assert.equal(createRetry.status, 201);
    assert.equal(createRetry.data.id, bookingId);

    // Creating a second live booking with a different key is blocked by partial unique index
    const secondLive = await api('POST', '/v1/bookings', {
      token: customerToken,
      body: {
        vehicleType: 'bike',
        issue: 'puncture',
        lat: 18.5204,
        lng: 73.8567,
      },
    });
    assert.equal(secondLive.status, 409);
    assert.equal(secondLive.data.error, 'ACTIVE_BOOKING_EXISTS');

    // Both online partners received the offer in Wave 1
    const offers1 = await api('GET', '/v1/partner/offers', { token: partner1Token });
    const offers2 = await api('GET', '/v1/partner/offers', { token: partner2Token });
    assert.equal(offers1.data.offers.length, 1);
    assert.equal(offers2.data.offers.length, 1);

    // Simultaneous race: Partner 1 and Partner 2 both click Accept at the exact same instant
    const [race1, race2] = await Promise.all([
      api('POST', `/v1/partner/bookings/${bookingId}/accept`, { token: partner1Token }),
      api('POST', `/v1/partner/bookings/${bookingId}/accept`, { token: partner2Token }),
    ]);
    const statuses = [race1.status, race2.status].sort();
    assert.deepEqual(statuses, [200, 409], 'Exactly one partner must win the accept race');

    const winnerToken = race1.status === 200 ? partner1Token : partner2Token;
    const loserToken = race1.status === 200 ? partner2Token : partner1Token;

    // Crucial privacy check: winner partner view NEVER includes startOtp, and loser cannot access booking at all
    const winnerView = await api('GET', `/v1/bookings/${bookingId}`, { token: winnerToken });
    assert.equal(winnerView.status, 200);
    assert.equal(winnerView.data.startOtp, undefined, 'Partner must NEVER receive startOtp from API');

    const loserView = await api('GET', `/v1/bookings/${bookingId}`, { token: loserToken });
    assert.equal(loserView.status, 403);

    const strangerView = await api('GET', `/v1/bookings/${bookingId}`, { token: strangerToken });
    assert.equal(strangerView.status, 403);

    // Winner cannot start work before marking arrived
    const earlyStart = await api('POST', `/v1/partner/bookings/${bookingId}/start`, {
      token: winnerToken,
      body: { otp: customerOtp },
    });
    assert.equal(earlyStart.status, 409);

    // Winner marks arrived
    const arrivedRes = await api('POST', `/v1/partner/bookings/${bookingId}/arrive`, { token: winnerToken });
    assert.equal(arrivedRes.status, 200);
    assert.equal(arrivedRes.data.status, 'arrived');

    // Wrong OTP is rejected and decrements remaining attempts
    const wrongOtp = customerOtp === '0000' ? '9999' : '0000';
    const badStart = await api('POST', `/v1/partner/bookings/${bookingId}/start`, {
      token: winnerToken,
      body: { otp: wrongOtp },
    });
    assert.equal(badStart.status, 400);
    assert.equal(badStart.data.error, 'INVALID_OTP');

    // Correct 4-digit OTP transitions to in_progress
    const goodStart = await api('POST', `/v1/partner/bookings/${bookingId}/start`, {
      token: winnerToken,
      body: { otp: customerOtp },
    });
    assert.equal(goodStart.status, 200);
    assert.equal(goodStart.data.status, 'in_progress');

    // Once repair is in_progress, cancellation is blocked
    const cancelDuringWork = await api('POST', `/v1/bookings/${bookingId}/cancel`, {
      token: customerToken,
      body: { reason: 'changed mind' },
    });
    assert.equal(cancelDuringWork.status, 409);
    assert.equal(cancelDuringWork.data.error, 'CANNOT_CANCEL');

    // Partner proposes an extra spare part charge (Rs 350 = 35000 paise)
    const addCh = await api('POST', `/v1/partner/bookings/${bookingId}/charges`, {
      token: winnerToken,
      body: { description: 'Exide Starter Relay', amountPaise: 35000 },
    });
    assert.equal(addCh.status, 200);
    const chargeId = addCh.data.charges[0].id;

    // Partner cannot complete the job while a charge is still pending customer decision
    const prematureComplete = await api('POST', `/v1/partner/bookings/${bookingId}/complete`, {
      token: winnerToken,
      body: { paymentMethod: 'upi' },
    });
    assert.equal(prematureComplete.status, 409);
    assert.equal(prematureComplete.data.error, 'PENDING_CHARGES');

    // Customer approves the extra charge
    const approveCh = await api('POST', `/v1/bookings/${bookingId}/charges/${chargeId}/decision`, {
      token: customerToken,
      body: { decision: 'approved' },
    });
    assert.equal(approveCh.status, 200);
    assert.equal(approveCh.data.extraPaise, 35000);
    assert.equal(approveCh.data.totalPaise, 59900);

    // Partner completes the job
    const completed = await api('POST', `/v1/partner/bookings/${bookingId}/complete`, {
      token: winnerToken,
      body: { paymentMethod: 'upi' },
    });
    assert.equal(completed.status, 200);
    assert.equal(completed.data.status, 'completed');

    // Check partner earnings & commission ledger (15% of 59900 = 8985 paise)
    const earnings = await api('GET', '/v1/partner/earnings', { token: winnerToken });
    assert.equal(earnings.status, 200);
    assert.equal(earnings.data.completedJobs, 1);
    assert.equal(earnings.data.grossPaise, 59900);
    assert.equal(earnings.data.commissionPaise, 8985);
    assert.equal(earnings.data.netEarningsPaise, 50915);
    assert.equal(earnings.data.commissionBalanceDuePaise, 8985);

    // Verify PostgreSQL trigger blocks UPDATE and DELETE on ledger_entries
    await assert.rejects(
      () => poolRef.query(`UPDATE ledger_entries SET amount_paise = 0`),
      /ledger_entries is append-only/,
    );
    await assert.rejects(
      () => poolRef.query(`DELETE FROM ledger_entries`),
      /ledger_entries is append-only/,
    );

    // Customer rates the completed booking
    const rateRes = await api('POST', `/v1/bookings/${bookingId}/rating`, {
      token: customerToken,
      body: { stars: 5, comment: 'Fast arrival and honest pricing' },
    });
    assert.equal(rateRes.status, 200);
    assert.equal(rateRes.data.rating.stars, 5);
    assert.equal(rateRes.data.partner.rating, 5);

    // Duplicate rating is blocked
    const dupRate = await api('POST', `/v1/bookings/${bookingId}/rating`, {
      token: customerToken,
      body: { stars: 1 },
    });
    assert.equal(dupRate.status, 409);

    socket.disconnect();
    assert.ok(eventsReceived.includes('accepted'));
    assert.ok(eventsReceived.includes('arrived'));
    assert.ok(eventsReceived.includes('in_progress'));
    assert.ok(eventsReceived.includes('completed'));
  });

  it('6. Brute-force 5 wrong OTP attempts locks the booking from starting', async () => {
    // Create a new booking and accept it
    const bRes = await api('POST', '/v1/bookings', {
      token: customerToken,
      body: {
        vehicleType: 'bike',
        issue: 'puncture',
        lat: 18.5204,
        lng: 73.8567,
      },
    });
    assert.equal(bRes.status, 201);
    const bId = bRes.data.id;
    const realOtp = bRes.data.startOtp;
    const wrong = realOtp === '1111' ? '2222' : '1111';

    await api('POST', `/v1/partner/bookings/${bId}/accept`, { token: partner1Token });
    await api('POST', `/v1/partner/bookings/${bId}/arrive`, { token: partner1Token });

    for (let i = 1; i <= 4; i++) {
      const r = await api('POST', `/v1/partner/bookings/${bId}/start`, {
        token: partner1Token,
        body: { otp: wrong },
      });
      assert.equal(r.status, 400);
    }

    // 5th wrong attempt locks OTP
    const fifth = await api('POST', `/v1/partner/bookings/${bId}/start`, {
      token: partner1Token,
      body: { otp: wrong },
    });
    assert.equal(fifth.status, 429);
    assert.equal(fifth.data.error, 'OTP_LOCKED');

    // Even the real OTP is rejected once locked
    const afterLock = await api('POST', `/v1/partner/bookings/${bId}/start`, {
      token: partner1Token,
      body: { otp: realOtp },
    });
    assert.equal(afterLock.status, 429);

    // Clean up by cancelling booking
    const cRes = await api('POST', `/v1/bookings/${bId}/cancel`, { token: customerToken });
    assert.equal(cRes.status, 200);
  });

  it('7. Dispatch wave escalation expires booking cleanly when no mechanic accepts', async () => {
    // Take both partners offline so no one accepts
    await api('POST', '/v1/partner/availability', { token: partner1Token, body: { isOnline: false } });
    await api('POST', '/v1/partner/availability', { token: partner2Token, body: { isOnline: false } });

    const bRes = await api('POST', '/v1/bookings', {
      token: customerToken,
      body: {
        vehicleType: 'scooter',
        issue: 'wont_start',
        lat: 18.5204,
        lng: 73.8567,
      },
    });
    assert.equal(bRes.status, 201);
    const bId = bRes.data.id;

    // Fast-forward next_dispatch_at in DB to simulate waves timing out
    for (let w = 0; w < 3; w++) {
      await poolRef.query(`UPDATE bookings SET next_dispatch_at = now() - interval '1 second' WHERE id = $1`, [bId]);
      await runDispatchTickRef();
    }

    const finalView = await api('GET', `/v1/bookings/${bId}`, { token: customerToken });
    assert.equal(finalView.data.status, 'expired');
  });
});
