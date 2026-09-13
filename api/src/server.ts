import { loadConfig } from './config.js';
import { buildApp } from './app.js';
import { connectMongo, disconnectMongo } from './db/connect.js';
import { mongoStore } from './services/mongo-store.js';
import { mongoCache, withMemory } from './cache/cache.js';
import { OpenAIProvider } from './llm/openai.js';

const config = loadConfig();
const app = buildApp({
  logLevel: config.LOG_LEVEL,
  store: mongoStore,
  cache: withMemory(mongoCache),
  llm: new OpenAIProvider(config.OPENAI_API_KEY),
  config,
  rateLimits: { lookups: config.RATE_LIMIT_LOOKUPS, llm: config.RATE_LIMIT_LLM },
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
