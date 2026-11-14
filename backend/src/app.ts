import Fastify, { FastifyInstance } from 'fastify';
import helmet from '@fastify/helmet';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import { config } from './config';
import { registerRoutes } from './routes';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: config.NODE_ENV === 'test' ? false : { level: config.LOG_LEVEL },
    trustProxy: true,
    bodyLimit: 64 * 1024, // 64 KB max JSON payload
  });

  await app.register(helmet, {
    global: true,
    contentSecurityPolicy: false,
  });

  await app.register(rateLimit, {
    global: true,
    max: 180,
    timeWindow: '1 minute',
  });

  await app.register(multipart, {
    limits: {
      files: 1,
      fields: 5,
      fileSize: 5 * 1024 * 1024, // 5 MB max KYC image
    },
  });

  await registerRoutes(app);
  return app;
}
