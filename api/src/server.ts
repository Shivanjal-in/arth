import { loadConfig } from './config.js';
import { buildApp } from './app.js';
import { connectMongo, disconnectMongo } from './db/connect.js';
import { mongoStore } from './services/mongo-store.js';
import { mongoCache, withMemory } from './cache/cache.js';
import { OpenAIProvider } from './llm/openai.js';
import { disabledVerifier, firebaseVerifier } from './auth/verifier.js';
import { firebaseApp, parseServiceAccount } from './auth/firebase-app.js';
import { disabledPusher, fcmPusher } from './push/pusher.js';
import { parseCloudinaryUrl } from './lib/cloudinary.js';
import { mongoAccountStore } from './services/mongo-accounts.js';
import { mongoCommunityStore } from './services/mongo-community.js';

const config = loadConfig();
const serviceAccount = parseServiceAccount(config.FIREBASE_SERVICE_ACCOUNT);
const fbApp = config.FIREBASE_PROJECT_ID ? firebaseApp(config.FIREBASE_PROJECT_ID, serviceAccount) : null;
const app = buildApp({
  logLevel: config.LOG_LEVEL,
  store: mongoStore,
  cache: withMemory(mongoCache),
  llm: new OpenAIProvider(config.OPENAI_API_KEY),
  config,
  rateLimits: { lookups: config.RATE_LIMIT_LOOKUPS, llm: config.RATE_LIMIT_LLM, prefetch: config.RATE_LIMIT_PREFETCH },
  accounts: {
    store: mongoAccountStore,
    verifier: fbApp ? firebaseVerifier(fbApp) : disabledVerifier,
    pusher: fbApp && serviceAccount ? fcmPusher(fbApp) : disabledPusher,
    cloudinary: parseCloudinaryUrl(config.CLOUDINARY_URL),
  },
  // Without a Firebase project nobody can sign in, so AI stays open.
  enforceQuota: config.FIREBASE_PROJECT_ID !== '',
  community: mongoCommunityStore,
  limits: { free: config.AI_FREE_LIMIT, proMonthly: config.AI_PRO_MONTHLY },
});

try {
  await connectMongo(config.MONGODB_URI);
  app.log.info({ uri: config.MONGODB_URI.replace(/\/\/.*@/, '//***@') }, 'mongo connected');
  await app.listen({ port: config.PORT, host: config.HOST });
} catch (err) {
  app.log.fatal({ err }, 'failed to start');
  process.exit(1);
}

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, async () => {
    app.log.info({ signal }, 'shutting down');
    await app.close();
    await disconnectMongo();
    process.exit(0);
  });
}
