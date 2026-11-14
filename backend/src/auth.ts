import { FastifyReply, FastifyRequest } from 'fastify';
import { config } from './config';
import { one, pool } from './db';
import { forbidden, unauthorized } from './errors';
import { verifyAppCheck, verifyIdToken } from './firebase';

export interface AuthUser {
  id: string;
  firebaseUid: string;
  phone: string;
  name: string | null;
  isAdmin: boolean;
}

declare module 'fastify' {
  interface FastifyRequest {
    user: AuthUser;
  }
}

interface CacheEntry {
  user: AuthUser;
  status: string;
  expires: number;
}

// Short-lived cache so we don't hit the DB on every request. Blocking a user takes effect within 30s.
const USER_CACHE_TTL_MS = 30_000;
const USER_CACHE_MAX = 50_000;
const userCache = new Map<string, CacheEntry>();

export function invalidateUserCache(firebaseUid?: string) {
  if (firebaseUid) userCache.delete(firebaseUid);
  else userCache.clear();
}

/** Resolves (and on first sight creates) the local user row for a verified Firebase identity. */
export async function resolveUser(uid: string, phone: string, isAdmin: boolean): Promise<{ user: AuthUser; status: string }> {
  const now = Date.now();
  const cached = userCache.get(uid);
  if (cached && cached.expires > now && cached.user.phone === phone) {
    return { user: { ...cached.user, isAdmin }, status: cached.status };
  }

  const row = await one<{ id: string; phone: string; name: string | null; status: string }>(
    pool,
    `INSERT INTO users (firebase_uid, phone) VALUES ($1, $2)
     ON CONFLICT (firebase_uid) DO UPDATE
       SET phone = EXCLUDED.phone,
           updated_at = CASE WHEN users.phone <> EXCLUDED.phone THEN now() ELSE users.updated_at END
     RETURNING id, phone, name, status`,
    [uid, phone],
  );
  if (!row) throw new Error('user upsert returned nothing');

  const user: AuthUser = { id: row.id, firebaseUid: uid, phone: row.phone, name: row.name, isAdmin };
  if (userCache.size >= USER_CACHE_MAX) {
    const firstKey = userCache.keys().next().value;
    if (firstKey !== undefined) userCache.delete(firstKey);
  }
  userCache.set(uid, { user, status: row.status, expires: now + USER_CACHE_TTL_MS });
  return { user, status: row.status };
}

function bearer(req: FastifyRequest): string | null {
  const h = req.headers.authorization;
  if (!h || !h.startsWith('Bearer ')) return null;
  const token = h.slice(7).trim();
  return token.length > 0 && token.length < 4096 ? token : null;
}

/** Fastify preHandler: every protected route goes through this. */
export async function authenticate(req: FastifyRequest, _reply: FastifyReply): Promise<void> {
  if (config.APP_CHECK_ENFORCE) {
    const ok = await verifyAppCheck(req.headers['x-firebase-appcheck'] as string | undefined);
    if (!ok) throw forbidden('APP_CHECK_FAILED', 'Unverified app');
  }
  const token = bearer(req);
  if (!token) throw unauthorized();
  const identity = await verifyIdToken(token);
  if (!identity) throw unauthorized('Session expired, please sign in again');

  const { user, status } = await resolveUser(identity.uid, identity.phone, identity.isAdmin);
  if (status !== 'active') throw forbidden('ACCOUNT_DISABLED', 'This account is disabled');
  req.user = user;
}

export async function requireAdmin(req: FastifyRequest, reply: FastifyReply): Promise<void> {
  await authenticate(req, reply);
  if (!req.user.isAdmin) throw forbidden();
}
