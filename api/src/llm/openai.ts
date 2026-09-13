import OpenAI from 'openai';
import type { ChatCompletionCreateParamsBase } from 'openai/resources/chat/completions';
import { ApiError, messages } from '../lib/errors.js';
import type { JsonRequest, JsonResult, LLMProvider, StreamChunk, Usage } from './provider.js';

function body(req: JsonRequest): ChatCompletionCreateParamsBase {
  return {
    model: req.model,
    messages: req.messages,
    response_format: {
      type: 'json_schema',
      json_schema: { name: req.schemaName, strict: true, schema: req.schema },
    },
    max_completion_tokens: req.maxOutputTokens,
    ...(req.temperature === undefined ? {} : { temperature: req.temperature }),
  };
}

function usageOf(u: OpenAI.CompletionUsage | null | undefined): Usage {
  return {
    input: u?.prompt_tokens ?? 0,
    output: u?.completion_tokens ?? 0,
    cachedInput: u?.prompt_tokens_details?.cached_tokens ?? 0,
  };
}

export class OpenAIProvider implements LLMProvider {
  private readonly client: OpenAI;

  constructor(apiKey: string) {
    this.client = new OpenAI({ apiKey, maxRetries: 1, timeout: 45_000 });
  }

  async completeJson(req: JsonRequest, signal?: AbortSignal): Promise<JsonResult> {
    try {
      const res = await this.client.chat.completions.create({ ...body(req), stream: false }, { signal });
      const choice = res.choices[0];
      const content = choice?.message.content;
      if (!content) throw new ApiError('UPSTREAM_FAILED', messages.upstreamFailed, { finish: choice?.finish_reason });
      return { content, usage: usageOf(res.usage), model: res.model };
    } catch (err) {
      throw toApiError(err);
    }
  }

  async *streamJson(req: JsonRequest, signal?: AbortSignal): AsyncIterable<StreamChunk> {
    let stream: AsyncIterable<OpenAI.ChatCompletionChunk>;
    try {
      stream = await this.client.chat.completions.create(
        { ...body(req), stream: true, stream_options: { include_usage: true } },
        { signal },
      );
    } catch (err) {
      throw toApiError(err);
    }
    let usage: Usage = { input: 0, output: 0, cachedInput: 0 };
    let model = req.model;
    try {
      for await (const chunk of stream) {
        model = chunk.model || model;
        const text = chunk.choices[0]?.delta?.content;
        if (text) yield { type: 'delta', text };
        if (chunk.usage) usage = usageOf(chunk.usage);
      }
    } catch (err) {
      throw toApiError(err);
    }
    yield { type: 'done', usage, model };
  }
}

function toApiError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;
  const status = (err as { status?: number }).status;
  if (status === 429) return new ApiError('RATE_LIMITED', messages.rateLimited, {}, { cause: err });
  return new ApiError('UPSTREAM_FAILED', messages.upstreamFailed, {}, { cause: err });
}
