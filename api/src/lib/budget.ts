/**
 * Per-device budget for model calls: a sliding one-minute window, in memory.
 * Spent only when a request actually reaches the model — cache hits and
 * single-sense bypasses are free, which is what "20 LLM calls a minute" means.
 */
export class LlmBudget {
  private readonly windows = new Map<string, number[]>();

  constructor(
    private readonly max: number,
    private readonly windowMs = 60_000,
  ) {}

  /** Returns true and records the call, or false if the key is over budget. */
  tryConsume(key: string, now = Date.now()): boolean {
    const cutoff = now - this.windowMs;
    const hits = (this.windows.get(key) ?? []).filter((t) => t > cutoff);
    if (hits.length >= this.max) {
      this.windows.set(key, hits);
      return false;
    }
    hits.push(now);
    this.windows.set(key, hits);
    if (this.windows.size > 50_000) this.sweep(cutoff);
    return true;
  }

  private sweep(cutoff: number): void {
    for (const [k, v] of this.windows) {
      if (!v.some((t) => t > cutoff)) this.windows.delete(k);
    }
  }
}
