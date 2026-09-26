import { createHash } from 'node:crypto';

/**
 * Signed direct uploads: the app sends the photo straight to Cloudinary with
 * a signature we compute here, so the API secret never ships in the app and
 * the image never passes through our server.
 * https://cloudinary.com/documentation/authentication_signatures
 */
export type CloudinaryConfig = { cloudName: string; apiKey: string; apiSecret: string };

/** Parses cloudinary://<api_key>:<api_secret>@<cloud_name>; null if unset or malformed. */
export function parseCloudinaryUrl(url: string): CloudinaryConfig | null {
  const m = /^cloudinary:\/\/([^:]+):([^@]+)@(.+)$/.exec(url.trim());
  if (!m) return null;
  return { apiKey: m[1]!, apiSecret: m[2]!, cloudName: m[3]! };
}

/** SHA-1 of the params sorted by key, joined as k=v&…, then the secret. */
export function signParams(params: Record<string, string | number>, apiSecret: string): string {
  const toSign = Object.keys(params)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('&');
  return createHash('sha1').update(toSign + apiSecret).digest('hex');
}

export type UploadTicket = {
  uploadUrl: string;
  apiKey: string;
  timestamp: number;
  signature: string;
  /** Signed params the app must send exactly as given. */
  params: Record<string, string>;
};

/**
 * One user's avatar: a fixed public id per user, so a new photo replaces
 * the old one; square-cropped on the face and capped at 512px on upload.
 */
export function avatarTicket(cfg: CloudinaryConfig, uid: string, now = Date.now()): UploadTicket {
  const timestamp = Math.floor(now / 1000);
  const params = {
    folder: 'arth/avatars',
    public_id: uid,
    overwrite: 'true',
    invalidate: 'true',
    transformation: 'c_fill,g_face,w_512,h_512,q_auto,f_auto',
  };
  return {
    uploadUrl: `https://api.cloudinary.com/v1_1/${cfg.cloudName}/image/upload`,
    apiKey: cfg.apiKey,
    timestamp,
    signature: signParams({ ...params, timestamp }, cfg.apiSecret),
    params,
  };
}

/** Deletes a user's avatar (see [avatarTicket]); a missing one is fine. */
export async function destroyAvatar(cfg: CloudinaryConfig, uid: string, fetchImpl: typeof fetch = fetch, now = Date.now()): Promise<void> {
  const timestamp = Math.floor(now / 1000);
  const params = { invalidate: 'true', public_id: `arth/avatars/${uid}`, timestamp };
  const body = new URLSearchParams({ ...Object.fromEntries(Object.entries(params).map(([k, v]) => [k, String(v)])), api_key: cfg.apiKey, signature: signParams(params, cfg.apiSecret) });
  const res = await fetchImpl(`https://api.cloudinary.com/v1_1/${cfg.cloudName}/image/destroy`, { method: 'POST', body });
  if (!res.ok) throw new Error(`Cloudinary ${res.status}`);
}
