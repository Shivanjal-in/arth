import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';

/** A Firebase service account, for sending push notifications. */
export type ServiceAccount = { projectId: string; clientEmail: string; privateKey: string };

/**
 * FIREBASE_SERVICE_ACCOUNT holds the key file Firebase downloads (Project
 * settings → Service accounts → Generate new private key), as raw JSON or
 * base64 of it. Null when unset or unreadable.
 */
export function parseServiceAccount(raw: string): ServiceAccount | null {
  const text = raw.trim();
  if (!text) return null;
  try {
    const json = JSON.parse(text.startsWith('{') ? text : Buffer.from(text, 'base64').toString('utf8')) as Record<string, string>;
    if (!json.project_id || !json.client_email || !json.private_key) return null;
    // Keys pasted into dashboards often arrive with literal "\n".
    return { projectId: json.project_id, clientEmail: json.client_email, privateKey: json.private_key.replace(/\\n/g, '\n') };
  } catch {
    return null;
  }
}

/**
 * The one Firebase admin app. Verifying sign-ins needs only the project id;
 * sending pushes needs the service account's credentials.
 */
export function firebaseApp(projectId: string, account: ServiceAccount | null): App {
  const existing = getApps().find((a) => a.name === 'arth');
  if (existing) return existing;
  return initializeApp(account ? { projectId, credential: cert(account) } : { projectId }, 'arth');
}
