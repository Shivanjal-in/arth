import type { ErrorCode } from './errors.js';

export type Ok<T> = { ok: true; data: T };
export type Fail = { ok: false; error: { code: ErrorCode; message: string } & Record<string, unknown> };
export type Envelope<T> = Ok<T> | Fail;

export const ok = <T>(data: T): Ok<T> => ({ ok: true, data });
export const fail = (code: ErrorCode, message: string, extra: Record<string, unknown> = {}): Fail => ({
  ok: false,
  error: { code, message, ...extra },
});
