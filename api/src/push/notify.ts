/**
 * What Arth tells readers, and sending it to every phone they're signed in
 * on, each in that phone's language. Three things fire notifications today:
 *
 *   review reminder   cards are due (daily at most; scripts/review-reminders.ts)
 *   plan changed      an admin set their tier (scripts/set-tier.ts)
 *   AI running low    10 free answers left, or 50 of a Pro month (ai-gate)
 *
 * Plus a test push a signed-in reader can send themselves.
 */
import type { AccountStore, Lang, Tier, User } from '../services/accounts.js';
import { allowanceFor, monthOf, type Limits } from '../services/quota.js';
import type { PushMessage, Pusher } from './pusher.js';

export type Localized = (lang: Lang) => PushMessage;

/** Sends to all of [uid]'s phones; forgets tokens FCM says are dead. */
export async function notifyUser(store: AccountStore, pusher: Pusher, uid: string, message: Localized): Promise<number> {
  if (!pusher.enabled) return 0;
  const devices = await store.pushDevices(uid);
  let sent = 0;
  const dead: string[] = [];
  for (const lang of ['en', 'hi'] as const) {
    const tokens = devices.filter((d) => d.lang === lang).map((d) => d.token);
    if (tokens.length === 0) continue;
    const r = await pusher.send(tokens, message(lang));
    sent += r.sent;
    dead.push(...r.invalid);
  }
  await store.removeDeadTokens(dead);
  return sent;
}

// ---- messages ----

export const testMessage: Localized = (lang) =>
  lang === 'hi'
    ? { title: 'Arth', body: 'सूचनाएँ चालू हैं। 🎉', route: '/settings' }
    : { title: 'Arth', body: 'Notifications are working. 🎉', route: '/settings' };

export function reviewMessage(total: number, topBook: string | null): Localized {
  return (lang) => {
    const book = topBook ? (lang === 'hi' ? ` — ज़्यादातर “${topBook}” से` : ` — most from “${topBook}”`) : '';
    return lang === 'hi'
      ? { title: 'दोहराने का समय', body: `${total} कार्ड आपका इंतज़ार कर रहे हैं${book}।`, route: '/cards', tag: 'review' }
      : { title: 'Time for a quick review', body: `${total === 1 ? '1 card is' : `${total} cards are`} ready${book}.`, route: '/cards', tag: 'review' };
  };
}

export function tierMessage(tier: Tier): Localized {
  return (lang) => {
    if (tier === 'free') {
      return lang === 'hi'
        ? { title: 'आपका प्लान बदला', body: 'अब आप फ़्री प्लान पर हैं।', route: '/plans', tag: 'plan' }
        : { title: 'Your plan changed', body: 'You’re on the Free plan now.', route: '/plans', tag: 'plan' };
    }
    const name = tier === 'pro' ? 'Pro' : 'Super';
    const hi = tier === 'pro' ? 'हर महीने 1,000 AI जवाब, बिना विज्ञापन।' : 'असीमित AI जवाब, बिना विज्ञापन।';
    const en = tier === 'pro' ? '1,000 AI answers a month, and no ads.' : 'Unlimited AI answers, and no ads.';
    return lang === 'hi'
      ? { title: `आप अब ${name} पर हैं ✨`, body: hi, route: '/plans', tag: 'plan' }
      : { title: `You’re on ${name} now ✨`, body: en, route: '/plans', tag: 'plan' };
  };
}

export function lowAiMessage(left: number, monthly: boolean): Localized {
  return (lang) =>
    lang === 'hi'
      ? {
          title: `${left} AI जवाब बाकी`,
          body: monthly ? 'इस महीने के AI जवाब खत्म होने वाले हैं।' : 'फ़्री AI जवाब खत्म होने वाले हैं। ऑफ़लाइन शब्दकोश चलता रहेगा।',
          route: '/plans',
          tag: 'ai-low',
        }
      : {
          title: `${left} AI answers left`,
          body: monthly ? 'This month’s AI answers are almost used up.' : 'Your free AI answers are almost used up. The offline dictionary keeps working.',
          route: '/plans',
          tag: 'ai-low',
        };
}

// ---- triggers ----

/** When a reader is this close to the end of their allowance, say so once. */
export const LOW_AI_AT = { free: 10, pro: 50 } as const;

/**
 * After an AI use: warn once per allowance period when exactly the
 * threshold is left. [user] is the state after the use was counted.
 */
export async function maybeWarnLowAi(store: AccountStore, pusher: Pusher, user: User, limits: Limits, now = Date.now()): Promise<boolean> {
  const a = allowanceFor(user.tier, limits);
  if (a.period === 'none' || user.tier === 'super') return false;
  const period = a.period === 'lifetime' ? 'lifetime' : monthOf(now);
  const used = a.period === 'lifetime' ? user.aiTotal : user.aiMonthUses;
  const left = a.max - used;
  const threshold = user.tier === 'free' ? LOW_AI_AT.free : LOW_AI_AT.pro;
  if (left !== threshold || user.lowAiNoticeFor === period) return false;
  await store.updateUser(user.uid, { lowAiNoticeFor: period });
  await notifyUser(store, pusher, user.uid, lowAiMessage(left, a.period === 'month'));
  return true;
}

/** Nudges everyone with cards due, at most once per [every]. */
export async function sendReviewReminders(
  store: AccountStore,
  pusher: Pusher,
  now = Date.now(),
  every = 20 * 60 * 60 * 1000,
): Promise<{ checked: number; reminded: number }> {
  const candidates = await store.reminderCandidates(now - every);
  let reminded = 0;
  for (const user of candidates) {
    const due = await store.dueCards(user.uid, now);
    if (due.total === 0) continue;
    if ((await notifyUser(store, pusher, user.uid, reviewMessage(due.total, due.topBook))) > 0) reminded++;
    await store.updateUser(user.uid, { lastReviewNudgeAt: now });
  }
  return { checked: candidates.length, reminded };
}
