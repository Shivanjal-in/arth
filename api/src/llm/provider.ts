/**
 * The one interface every model call goes through. Route handlers never touch
 * an SDK. Model names come from config, never from code.
 */

export type Usage = { input: number; output: number; cachedInput: number };

export type ChatMessage = { role: 'system' | 'user' | 'assistant'; content: string };

export type JsonRequest = {
  model: string;
  /** System prompt + fixed gold examples first, so prompt caching applies. */
  messages: ChatMessage[];
  schemaName: string;
  /** JSON Schema from contracts/, Structured Outputs strict mode. */
  schema: Record<string, unknown>;
  maxOutputTokens: number;
  /** Omitted when undefined — the gpt-5.6 family rejects the parameter. */
  temperature?: number;
};

export type JsonResult = {
  content: string;
  usage: Usage;
  model: string;
};

export type StreamChunk =
  | { type: 'delta'; text: string }
  | { type: 'done'; usage: Usage; model: string };

export interface LLMProvider {
  completeJson(req: JsonRequest, signal?: AbortSignal): Promise<JsonResult>;
  /** Text deltas of the JSON object, then a final usage chunk. */
  streamJson(req: JsonRequest, signal?: AbortSignal): AsyncIterable<StreamChunk>;
}

export const zeroUsage: Usage = { input: 0, output: 0, cachedInput: 0 };

export const addUsage = (a: Usage, b: Usage): Usage => ({
  input: a.input + b.input,
  output: a.output + b.output,
  cachedInput: a.cachedInput + b.cachedInput,
});
