/**
 * Sends "cards are ready to review" to everyone with cards due, at most
 * once a day each. Run once a day (Render cron job in render.yaml):
 *
 *   npm run review-reminders
 */
import { loadConfig } from '../src/config.js';
import { connectMongo, disconnectMongo } from '../src/db/connect.js';
import { firebaseApp, parseServiceAccount } from '../src/auth/firebase-app.js';
import { fcmPusher } from '../src/push/pusher.js';
import { sendReviewReminders } from '../src/push/notify.js';
import { mongoAccountStore } from '../src/services/mongo-accounts.js';

const config = loadConfig();
const account = parseServiceAccount(config.FIREBASE_SERVICE_ACCOUNT);
if (!config.FIREBASE_PROJECT_ID || !account) {
  console.error('FIREBASE_PROJECT_ID and FIREBASE_SERVICE_ACCOUNT are needed to send notifications');
  process.exit(2);
}
await connectMongo(config.MONGODB_URI);
try {
  const result = await sendReviewReminders(mongoAccountStore, fcmPusher(firebaseApp(config.FIREBASE_PROJECT_ID, account)));
  console.log(`checked ${result.checked} readers, reminded ${result.reminded}`);
} finally {
  await disconnectMongo();
}
