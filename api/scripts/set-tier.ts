/**
 * Sets a user's tier (and optionally makes them an admin) until there's an
 * admin screen and payments. Find them by Firebase uid, email or phone.
 *
 *   npm run set-tier -- reader@example.com pro
 *   npm run set-tier -- +919876543210 super
 *   npm run set-tier -- <uid> free --admin
 *
 * This sets the *granted* plan. Someone with a store subscription keeps
 * the higher of the two.
 */
import { loadConfig } from '../src/config.js';
import { connectMongo, disconnectMongo } from '../src/db/connect.js';
import { UserModel } from '../src/db/models/account.js';
import { firebaseApp, parseServiceAccount } from '../src/auth/firebase-app.js';
import { fcmPusher } from '../src/push/pusher.js';
import { notifyUser, tierMessage } from '../src/push/notify.js';
import { mongoAccountStore } from '../src/services/mongo-accounts.js';
import { higherTier, type Tier } from '../src/services/accounts.js';

const [who, tier, ...flags] = process.argv.slice(2);
if (!who || !['free', 'pro', 'super'].includes(tier ?? '')) {
  console.error('usage: npm run set-tier -- <uid|email|phone> <free|pro|super> [--admin|--no-admin] [--quiet]');
  process.exit(2);
}

const config = loadConfig();
await connectMongo(config.MONGODB_URI);
try {
  const match = { $or: [{ _id: who }, { email: who }, { phone: who }] };
  const found = await UserModel.findOne(match).lean();
  // This grants a plan; one bought in the store (storeTier) still counts.
  const set: Record<string, unknown> = { grantTier: tier, tier: higherTier(tier as Tier, (found?.storeTier as Tier | undefined) ?? 'free'), updatedAt: Date.now() };
  if (flags.includes('--admin')) set.role = 'admin';
  if (flags.includes('--no-admin')) set.role = 'user';
  // The document as it was: its old tier tells whether anything changed.
  const before = found && (await UserModel.findOneAndUpdate({ _id: found._id }, { $set: set }, { new: false }).lean());
  const user = before && { ...before, ...set };
  if (!user) {
    console.error(`no user matches ${who} — they appear after their first sign-in`);
    process.exitCode = 1;
  } else {
    console.log(`${user._id} (${user.email ?? user.phone ?? user.displayName}) → tier ${user.tier}, role ${user.role}`);
    // Tell them, on every phone they're signed in on (skipped with --quiet
    // or without a service account).
    const account = parseServiceAccount(config.FIREBASE_SERVICE_ACCOUNT);
    if (!flags.includes('--quiet') && account && config.FIREBASE_PROJECT_ID && before?.tier !== user.tier) {
      const pusher = fcmPusher(firebaseApp(config.FIREBASE_PROJECT_ID, account));
      const sent = await notifyUser(mongoAccountStore, pusher, user._id, tierMessage(user.tier as Tier));
      console.log(`notified ${sent} device(s)`);
    }
  }
} finally {
  await disconnectMongo();
}
