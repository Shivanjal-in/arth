/** Typed, coded errors. Route handlers throw these; the app-level error handler maps them to the envelope. */

export type ErrorCode = 'NOT_FOUND' | 'BAD_REQUEST' | 'RATE_LIMITED' | 'UPSTREAM_FAILED' | 'INTERNAL';

const STATUS: Record<ErrorCode, number> = {
  NOT_FOUND: 404,
  BAD_REQUEST: 400,
  RATE_LIMITED: 429,
  UPSTREAM_FAILED: 502,
  INTERNAL: 500,
};

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  /** Fastify and its plugins read `statusCode`; keep both in step. */
  get statusCode(): number {
    return this.status;
  }
  /** Extra fields merged into the `error` object (e.g. `suggestions`). */
  readonly extra: Record<string, unknown>;

  constructor(code: ErrorCode, message: string, extra: Record<string, unknown> = {}, options?: ErrorOptions) {
    super(message, options);
    this.name = 'ApiError';
    this.code = code;
    this.status = STATUS[code];
    this.extra = extra;
  }
}

/** User-facing Hindi messages. Keep them short; the UI shows them verbatim. */
export const messages = {
  wordNotFound: 'यह शब्द शब्दकोश में नहीं मिला।',
  badRequest: 'अनुरोध सही नहीं है।',
  rateLimited: 'बहुत जल्दी-जल्दी अनुरोध हो रहे हैं। एक मिनट रुककर फिर कोशिश करें।',
  llmRateLimited: 'एक मिनट में बहुत सारे अर्थ माँगे गए हैं। थोड़ा रुककर फिर कोशिश करें।',
  upstreamFailed: 'अभी अर्थ नहीं मिल पाया। थोड़ी देर बाद फिर कोशिश करें।',
  internal: 'कुछ गड़बड़ हो गई। थोड़ी देर बाद फिर कोशिश करें।',
} as const;
