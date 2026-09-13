import type { FastifyPluginAsync } from 'fastify';
import mongoose from 'mongoose';
import { ok } from '../lib/envelope.js';
import { cacheStats } from '../cache/cache.js';

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/health', async () => {
    const total = cacheStats.hits + cacheStats.misses;
    return ok({
      mongo: mongoose.connection.readyState === 1 ? 'up' : 'down',
      cache: { ...cacheStats, hitRate: total === 0 ? null : Number((cacheStats.hits / total).toFixed(3)) },
    });
  });
};
