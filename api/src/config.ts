import { z } from 'zod';

const EnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  HOST: z.string().default('0.0.0.0'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  MONGODB_URI: z.string().url(),

  // --- LLM (Phase 3) ---
  OPENAI_API_KEY: z.string().default(''),
  LLM_CONTEXT_MODEL: z.string().default('gpt-5.6-luna'),
  LLM_TRANSLATE_MODEL: z.string().default('gpt-5.6-luna'),
  /** Model for the index-only context path (a nano-class model once one is named). */
  LLM_CONTEXT_INDEX_MODEL: z.string().default('gpt-5.6-luna'),
  /** On-demand dictionary entries for staged lemmas (same prompt as the pipeline). */
  LLM_ENTRY_MODEL: z.string().default('gpt-5.6-luna'),
  LLM_ENTRY_MAX_TOKENS: z.coerce.number().int().default(4000),
  /** live: model picks the sense and writes the note. index: model picks the sense; note is pre-written. */
  CONTEXT_MODE: z.enum(['live', 'index']).default('live'),
  LLM_TEMPERATURE: z.coerce.number().optional(),
  // Includes hidden reasoning tokens on the gpt-5.6 family; the visible note is ~100.
  LLM_CONTEXT_MAX_TOKENS: z.coerce.number().int().default(900),
  LLM_TRANSLATE_MAX_TOKENS: z.coerce.number().int().default(1200),

  // --- rate limits per device, per minute (Section 6) ---
  RATE_LIMIT_LOOKUPS: z.coerce.number().int().default(60),
  RATE_LIMIT_LLM: z.coerce.number().int().default(20),
  /** Background prefetch (X-Prefetch: 1) has its own bucket so it never starves taps. */
  RATE_LIMIT_PREFETCH: z.coerce.number().int().default(40),

  // --- accounts ---
  /** Firebase project whose ID tokens we accept. Unset: account routes answer 503. */
  FIREBASE_PROJECT_ID: z.string().default(''),
  /** cloudinary://<api_key>:<api_secret>@<cloud_name>. Unset: avatar uploads answer 503. */
  CLOUDINARY_URL: z.string().default(''),
  /** Service-account key (JSON, or base64 of it), for sending notifications. Unset: none are sent. */
  FIREBASE_SERVICE_ACCOUNT: z.string().default(''),

  // --- AI allowances (enforced only when accounts are on) ---
  AI_FREE_LIMIT: z.coerce.number().int().positive().default(100),
  AI_PRO_MONTHLY: z.coerce.number().int().positive().default(1000),
});

export type Config = z.infer<typeof EnvSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = EnvSchema.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid environment: ${issues}`);
  }
  return parsed.data;
}
