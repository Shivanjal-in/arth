import type { App } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

/** One notification, and where tapping it should take the reader. */
export type PushMessage = {
  title: string;
  body: string;
  /** An app route (`/cards`, `/plans`); the app opens it on tap. */
  route?: string;
  /** Collapses repeats of the same kind (a new review reminder replaces the old one). */
  tag?: string;
};

export interface Pusher {
  readonly enabled: boolean;
  /** Sends to [tokens]; returns the tokens FCM says are gone for good. */
  send(tokens: string[], message: PushMessage): Promise<{ sent: number; invalid: string[] }>;
}

/** FCM error codes that mean "this token will never work again". */
const DEAD = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token', 'messaging/invalid-argument']);

export function fcmPusher(app: App): Pusher {
  const messaging = getMessaging(app);
  return {
    enabled: true,
    async send(tokens, m) {
      if (tokens.length === 0) return { sent: 0, invalid: [] };
      const res = await messaging.sendEachForMulticast({
        tokens,
        notification: { title: m.title, body: m.body },
        data: m.route ? { route: m.route } : {},
        android: {
          priority: 'high',
          notification: { channelId: 'arth_default', ...(m.tag ? { tag: m.tag } : {}) },
          ...(m.tag ? { collapseKey: m.tag } : {}),
        },
        apns: {
          payload: { aps: { sound: 'default' } },
          ...(m.tag ? { headers: { 'apns-collapse-id': m.tag } } : {}),
        },
      });
      const invalid: string[] = [];
      res.responses.forEach((r, i) => {
        if (!r.success && DEAD.has(r.error?.code ?? '')) invalid.push(tokens[i]!);
      });
      return { sent: res.successCount, invalid };
    },
  };
}

/** No service account configured: nothing is sent. */
export const disabledPusher: Pusher = {
  enabled: false,
  async send() {
    return { sent: 0, invalid: [] };
  },
};

/** Records what would have been sent; tests. */
export class FakePusher implements Pusher {
  readonly enabled = true;
  readonly sent: { tokens: string[]; message: PushMessage }[] = [];
  /** Tokens to report as dead. */
  dead = new Set<string>();

  async send(tokens: string[], message: PushMessage) {
    this.sent.push({ tokens, message });
    return { sent: tokens.length, invalid: tokens.filter((t) => this.dead.has(t)) };
  }
}
