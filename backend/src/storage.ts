import fs from 'node:fs/promises';
import path from 'node:path';
import { config } from './config';
import { bucket } from './firebase';

export type ImageType = 'image/jpeg' | 'image/png' | 'image/webp';

/** Identify an image by its magic bytes. The client-declared content type is never trusted. */
export function sniffImage(buf: Buffer): ImageType | null {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return 'image/png';
  }
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  return null;
}

/**
 * Stores a private KYC file. Paths are generated server-side from the user id; the client
 * never controls the path. Files are never publicly readable.
 */
export async function storePrivateFile(objectPath: string, data: Buffer, contentType: ImageType): Promise<void> {
  if (bucket) {
    await bucket.file(objectPath).save(data, {
      contentType,
      resumable: false,
      metadata: { cacheControl: 'private, max-age=0' },
    });
    return;
  }
  const full = path.resolve(config.LOCAL_UPLOAD_DIR, objectPath);
  const root = path.resolve(config.LOCAL_UPLOAD_DIR);
  if (!full.startsWith(root + path.sep)) throw new Error('invalid storage path');
  await fs.mkdir(path.dirname(full), { recursive: true });
  await fs.writeFile(full, data);
}
