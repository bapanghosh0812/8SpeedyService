import { z } from 'zod';

const bool = z
  .enum(['true', 'false', '1', '0'])
  .optional()
  .transform((v) => v === 'true' || v === '1');

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8080),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  DB_POOL_MAX: z.coerce.number().int().positive().default(10),
  DB_SSL: bool,

  // Firebase project used for Phone Auth, FCM push and (optionally) App Check.
  FIREBASE_PROJECT_ID: z.string().min(1, 'FIREBASE_PROJECT_ID is required'),
  // Base64 of the service-account JSON. Not needed on Cloud Run (uses the runtime identity)
  // or when FIREBASE_AUTH_EMULATOR_HOST is set for local tests.
  FIREBASE_SERVICE_ACCOUNT_B64: z.string().optional(),
  FIREBASE_AUTH_EMULATOR_HOST: z.string().optional(),
  APP_CHECK_ENFORCE: bool,

  // KYC document storage: a GCS bucket in production, a local folder in development.
  STORAGE_BUCKET: z.string().optional(),
  LOCAL_UPLOAD_DIR: z.string().default('./data/uploads'),

  COMMISSION_BPS: z.coerce.number().int().min(0).max(5000).default(1500),
  SOCKET_ADAPTER: z.enum(['memory', 'postgres']).default('memory'),
  DISPATCH_WORKER: bool.default('true'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  // Seconds a partner has to accept an offer, and the dispatch radii per wave (metres).
  OFFER_TTL_SECONDS: z.coerce.number().int().min(5).max(120).default(20),
  DISPATCH_RADII_M: z
    .string()
    .default('3000,6000,10000')
    .transform((s) => s.split(',').map((x) => Number(x.trim())))
    .pipe(z.array(z.number().int().positive()).min(1)),
});

export type Config = z.infer<typeof EnvSchema>;

function load(): Config {
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  const cfg = parsed.data;
  if (cfg.NODE_ENV === 'production') {
    if (cfg.FIREBASE_AUTH_EMULATOR_HOST) {
      throw new Error('FIREBASE_AUTH_EMULATOR_HOST must never be set in production');
    }
    if (!cfg.STORAGE_BUCKET) {
      throw new Error('STORAGE_BUCKET is required in production');
    }
  }
  return cfg;
}

export const config: Config = load();
export const isProd = config.NODE_ENV === 'production';
