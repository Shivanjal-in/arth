import type { App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { ApiError, messages } from '../lib/errors.js';

/** What a verified sign-in tells us about the person. */
export type Claims = {
  uid: string;
  email?: string | undefined;
  phone?: string | undefined;
  name?: string | undefined;
  picture?: string | undefined;
};

export interface TokenVerifier {
  /** Throws ApiError UNAUTHORIZED for a bad or expired token. */
  verify(idToken: string): Promise<Claims>;
}

/**
 * Firebase ID tokens. Verification needs only the project id: the signing
 * keys are Google's public certificates, fetched and cached by firebase-admin.
 */
export function firebaseVerifier(app: App): TokenVerifier {
  const auth = getAuth(app);
  return {
    async verify(idToken) {
      try {
        const t = await auth.verifyIdToken(idToken);
        return {
          uid: t.uid,
          email: t.email,
          phone: t.phone_number,
          name: typeof t.name === 'string' ? t.name : undefined,
          picture: t.picture,
        };
      } catch (err) {
        const expired = (err as { code?: string }).code === 'auth/id-token-expired';
        throw new ApiError('UNAUTHORIZED', expired ? messages.signInExpired : messages.signInRequired, {}, { cause: err });
      }
    },
  };
}

/** No Firebase project configured: every account route is unavailable. */
export const disabledVerifier: TokenVerifier = {
  async verify() {
    throw new ApiError('UNAVAILABLE', messages.accountsUnavailable);
  },
};
