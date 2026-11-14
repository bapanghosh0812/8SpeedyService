import type { Server as HttpServer } from 'node:http';
import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/postgres-adapter';
import { resolveUser } from './auth';
import { config } from './config';
import { pool } from './db';
import { verifyAppCheck, verifyIdToken } from './firebase';

let io: Server | null = null;

/**
 * Realtime channel. Clients never choose rooms: each socket is placed only in its own
 * `user:<id>` room after token verification, so nobody can listen to someone else's booking.
 */
export function initRealtime(server: HttpServer, log: { info: (m: string) => void }): Server {
  io = new Server(server, {
    path: '/socket.io',
    transports: ['websocket'], // no long-polling => no sticky sessions needed behind a load balancer
    serveClient: false,
    maxHttpBufferSize: 16 * 1024,
    pingInterval: 20_000,
    pingTimeout: 20_000,
    cors: { origin: false },
  });

  if (config.SOCKET_ADAPTER === 'postgres') {
    io.adapter(createAdapter(pool));
    log.info('[realtime] using postgres adapter (multi-instance)');
  }

  io.use(async (socket, next) => {
    try {
      if (config.APP_CHECK_ENFORCE) {
        const ok = await verifyAppCheck(socket.handshake.auth?.appCheck as string | undefined);
        if (!ok) return next(new Error('APP_CHECK_FAILED'));
      }
      const token = socket.handshake.auth?.token;
      if (typeof token !== 'string') return next(new Error('UNAUTHENTICATED'));
      const identity = await verifyIdToken(token);
      if (!identity) return next(new Error('UNAUTHENTICATED'));
      const { user, status } = await resolveUser(identity.uid, identity.phone, identity.isAdmin);
      if (status !== 'active') return next(new Error('ACCOUNT_DISABLED'));
      socket.data.userId = user.id;
      next();
    } catch {
      next(new Error('UNAUTHENTICATED'));
    }
  });

  io.on('connection', (socket) => {
    void socket.join(`user:${socket.data.userId}`);
    // Clients may not send anything meaningful over the socket; all writes go through the HTTP API.
    socket.onAny(() => undefined);
  });

  return io;
}

export function emitToUser(userId: string, event: string, payload: unknown): void {
  io?.to(`user:${userId}`).emit(event, payload);
}

export async function closeRealtime(): Promise<void> {
  if (io) {
    await new Promise<void>((resolve) => io!.close(() => resolve()));
    io = null;
  }
}
