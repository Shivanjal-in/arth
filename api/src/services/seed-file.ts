import { createHash } from 'node:crypto';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { createGzip } from 'node:zlib';

/**
 * The whole on-device dictionary as one gzipped NDJSON file (GET
 * /v1/seed/file), built once per dictionary version and kept in memory.
 *
 * Streaming the seed straight out of Mongo takes about 50 s however fast the
 * phone is, and a phone that loses signal part-way has to start over. A built
 * file goes out at network speed, has a length, and can be resumed with a
 * Range request; its ETag is a hash of the bytes, so a resume against a
 * rebuilt (or another instance's) file is refused and starts over instead of
 * splicing two files together.
 */
export type SeedFile = {
  body: Buffer;
  etag: string;
  /** The SeedSource version it was built from. */
  version: string;
  builtAt: number;
};

export type SeedSource = {
  /** Changes whenever what the full seed would contain changes. Cheap. */
  version(): Promise<string>;
  /** The full seed's NDJSON lines, without newlines. */
  lines(): AsyncIterable<string>;
};

export type SeedFileOptions = {
  /** How often a request may trigger a version check. */
  recheckMs?: number;
  /** Rebuild at least this often, for changes the version can't see. */
  maxAgeMs?: number;
  now?: () => number;
  log?: { info: (obj: object, msg: string) => void; warn: (obj: object, msg: string) => void };
};

export class SeedFileCache {
  private file: SeedFile | null = null;
  private building: Promise<SeedFile> | null = null;
  private checkedAt = 0;
  private readonly recheckMs: number;
  private readonly maxAgeMs: number;
  private readonly now: () => number;

  constructor(
    private readonly source: SeedSource,
    private readonly opts: SeedFileOptions = {},
  ) {
    this.recheckMs = opts.recheckMs ?? 5 * 60_000;
    this.maxAgeMs = opts.maxAgeMs ?? 24 * 60 * 60_000;
    this.now = opts.now ?? Date.now;
  }

  /**
   * The file to serve. Waits for the first build; after that answers at once
   * and, now and then, checks the version in the background and swaps in a
   * rebuilt file when it has changed.
   */
  async current(): Promise<SeedFile> {
    const file = this.file;
    if (!file) return this.build();
    const now = this.now();
    if (now - this.checkedAt >= this.recheckMs && !this.building) {
      this.checkedAt = now;
      void this.refresh(file).catch((err: unknown) => this.opts.log?.warn({ err }, 'seed file refresh failed'));
    }
    return file;
  }

  /** Build ahead of the first request (server start). Never throws. */
  warm(): void {
    void this.current().catch((err: unknown) => this.opts.log?.warn({ err }, 'seed file build failed'));
  }

  private async refresh(file: SeedFile): Promise<void> {
    const stale = this.now() - file.builtAt >= this.maxAgeMs;
    if (stale || (await this.source.version()) !== file.version) await this.build();
  }

  /** One build at a time; concurrent callers share it. */
  private build(): Promise<SeedFile> {
    this.building ??= this.buildOnce().finally(() => {
      this.building = null;
    });
    return this.building;
  }

  private async buildOnce(): Promise<SeedFile> {
    const started = this.now();
    const version = await this.source.version();
    const source = this.source;
    const chunks: Buffer[] = [];
    await pipeline(
      Readable.from((async function* () {
        for await (const line of source.lines()) yield line + '\n';
      })()),
      // Built once, served many times: worth the slowest level.
      createGzip({ level: 9 }),
      async function (gzipped: AsyncIterable<Buffer>) {
        for await (const chunk of gzipped) chunks.push(chunk);
      },
    );
    const body = Buffer.concat(chunks);
    const etag = `"${createHash('sha1').update(body).digest('hex').slice(0, 20)}"`;
    const file: SeedFile = { body, etag, version, builtAt: this.now() };
    this.file = file;
    this.checkedAt = file.builtAt;
    this.opts.log?.info({ bytes: body.length, ms: file.builtAt - started, version }, 'seed file built');
    return file;
  }
}

/**
 * A byte range from a Range header, against a body of [size] bytes: the
 * first range of a `bytes=` header, `'unsatisfiable'`, or null when there is
 * no usable header (send the whole body).
 */
export function parseRange(header: string | undefined, size: number): { start: number; end: number } | 'unsatisfiable' | null {
  const m = /^bytes=(\d*)-(\d*)(?:,|$)/.exec(header?.trim() ?? '');
  if (!m) return null;
  const [, from, to] = m;
  if (from === '' && to === '') return null;
  let start: number;
  let end: number;
  if (from === '') {
    // bytes=-N: the last N bytes.
    const n = Number(to);
    if (n === 0) return 'unsatisfiable';
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = Number(from);
    end = to === '' ? size - 1 : Math.min(Number(to), size - 1);
  }
  if (start >= size || start > end) return 'unsatisfiable';
  return { start, end };
}
