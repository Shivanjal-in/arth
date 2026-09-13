import type { FastifyPluginAsync } from 'fastify';
import mongoose from 'mongoose';
import { ok } from '../lib/envelope.js';

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get('/health', async () => ok({ mongo: mongoose.connection.readyState === 1 ? 'up' : 'down' }));
};
