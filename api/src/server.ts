import { loadConfig } from './config.js';
import { buildApp } from './app.js';
import { connectMongo, disconnectMongo } from './db/connect.js';
import { mongoLemmaStore } from './services/mongo-store.js';

const config = loadConfig();
const app = buildApp({ logLevel: config.LOG_LEVEL, store: mongoLemmaStore });

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
