/** Content-hash cache over the `cache` collection. No TTL: books don't change. */
import { CacheModel } from '../db/models/index.js';

export type CacheKind = 'context' | 'sentence' | 'context-index' | 'cover';

export interface CacheStore {
  get<T>(key: string): Promise<T | null>;
  set(key: string, kind: CacheKind, data: unknown): Promise<void>;
}

export const mongoCache: CacheStore = {
  async get<T>(key: string): Promise<T | null> {
    const doc = await CacheModel.findByIdAndUpdate(key, { $inc: { hits: 1 } }, { new: false }).lean();
    return (doc?.data as T | undefined) ?? null;
  },
  async set(key: string, kind: CacheKind, data: unknown): Promise<void> {
    await CacheModel.updateOne({ _id: key }, { $setOnInsert: { kind, data, hits: 0, createdAt: new Date() } }, { upsert: true });
  },
};

export class MemoryCache implements CacheStore {
  readonly map = new Map<string, unknown>();
  async get<T>(key: string): Promise<T | null> {
    return (this.map.get(key) as T | undefined) ?? null;
  }
  async set(key: string, _kind: CacheKind, data: unknown): Promise<void> {
    this.map.set(key, data);
  }
}

/** Process-wide hit/miss counters, surfaced on /health and in the request log. */
export const cacheStats = { hits: 0, misses: 0 };

/**
 * Small in-process LRU in front of a CacheStore. Mongo is the durable cache;
 * this makes repeats within one process ~1 ms instead of an Atlas round trip.
 */
export function withMemory(store: CacheStore, max = 5000): CacheStore {
  const mem = new Map<string, unknown>();
  const remember = (key: string, data: unknown) => {
    mem.delete(key);
    mem.set(key, data);
    if (mem.size > max) mem.delete(mem.keys().next().value as string);
  };
  return {
    async get<T>(key: string): Promise<T | null> {
      if (mem.has(key)) {
        const v = mem.get(key) as T;
        remember(key, v);
        return v;
      }
      const v = await store.get<T>(key);
      if (v !== null) remember(key, v);
      return v;
    },
    async set(key: string, kind: CacheKind, data: unknown): Promise<void> {
      remember(key, data);
      await store.set(key, kind, data);
    },
  };
}
