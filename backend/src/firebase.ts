import { App, applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getAppCheck } from 'firebase-admin/app-check';
import { DecodedIdToken, getAuth } from 'firebase-admin/auth';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import { config } from './config';

function init(): App {
  const base = { projectId: config.FIREBASE_PROJECT_ID, storageBucket: config.STORAGE_BUCKET };
  if (config.FIREBASE_SERVICE_ACCOUNT_B64) {
    const json = JSON.parse(Buffer.from(config.FIREBASE_SERVICE_ACCOUNT_B64, 'base64').toString('utf8'));
    return initializeApp({ ...base, credential: cert(json) });
  }
  if (config.FIREBASE_AUTH_EMULATOR_HOST) {
    // firebase-admin reads FIREBASE_AUTH_EMULATOR_HOST from process.env itself.
    return initializeApp(base);
  }
  // Cloud Run / GCE: use the service's runtime identity.
  return initializeApp({ ...base, credential: applicationDefault() });
}

export const firebaseApp = init();
export const firebaseAuth = getAuth(firebaseApp);

/** Push and storage need real Google credentials; they are disabled when running against the emulator only. */
export const hasGoogleCredentials = !config.FIREBASE_AUTH_EMULATOR_HOST || Boolean(config.FIREBASE_SERVICE_ACCOUNT_B64);
export const messaging = hasGoogleCredentials ? getMessaging(firebaseApp) : null;
export const bucket = config.STORAGE_BUCKET && hasGoogleCredentials ? getStorage(firebaseApp).bucket() : null;

export interface VerifiedIdentity {
  uid: string;
  phone: string;
  isAdmin: boolean;
}

/**
 * Verifies a Firebase ID token (signature, expiry, audience = our project).
 * Only phone-number sign-ins are accepted: every account in this system is a verified phone.
 */
export async function verifyIdToken(token: string): Promise<VerifiedIdentity | null> {
  let decoded: DecodedIdToken;
  try {
    if (config.FIREBASE_AUTH_EMULATOR_HOST) {
      decoded = await (firebaseAuth as any).idTokenVerifier.verifyJWT(token, true);
    } else {
      decoded = await firebaseAuth.verifyIdToken(token);
    }
  } catch {
    return null;
  }
  const phone = decoded.phone_number;
  if (!phone || decoded.firebase?.sign_in_provider !== 'phone') return null;
  if (!/^\+91\d{10}$/.test(phone)) return null; // India-only service
  return { uid: decoded.uid, phone, isAdmin: decoded.admin === true };
}

export async function verifyAppCheck(token: string | undefined): Promise<boolean> {
  if (!token) return false;
  try {
    await getAppCheck(firebaseApp).verifyToken(token);
    return true;
  } catch {
    return false;
  }
}
