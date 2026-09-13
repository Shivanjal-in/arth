/**
 * Extracts completed top-level fields from a partial JSON object as it streams.
 *
 * Structured Outputs emit keys in schema order, so for TranslationResult the
 * model finishes `hindi` long before `difficultWords`. Scanning the buffer for
 * complete top-level values lets /translate push each field the moment it
 * closes, instead of waiting for the whole object.
 */
export function completedTopLevelFields(buffer: string): Map<string, unknown> {
  const out = new Map<string, unknown>();
  let i = 0;
  const n = buffer.length;
  // Skip to the opening brace.
  while (i < n && buffer[i] !== '{') i++;
  if (i >= n) return out;
  i++;
  for (;;) {
    // key
    const keyStart = buffer.indexOf('"', i);
    if (keyStart === -1) return out;
    const keyEnd = scanString(buffer, keyStart);
    if (keyEnd === -1) return out;
    const key = JSON.parse(buffer.slice(keyStart, keyEnd + 1)) as string;
    i = keyEnd + 1;
    while (i < n && buffer[i] !== ':') i++;
    if (i >= n) return out;
    i++;
    while (i < n && /\s/.test(buffer[i]!)) i++;
    if (i >= n) return out;
    const valueEnd = scanValue(buffer, i);
    if (valueEnd === -1) return out;
    try {
      out.set(key, JSON.parse(buffer.slice(i, valueEnd + 1)));
    } catch {
      return out;
    }
    i = valueEnd + 1;
    while (i < n && /[\s,]/.test(buffer[i]!)) i++;
    if (i >= n || buffer[i] === '}') return out;
  }
}

/** Index of the closing quote of the string starting at `start`, or -1 if incomplete. */
function scanString(s: string, start: number): number {
  for (let i = start + 1; i < s.length; i++) {
    const c = s[i];
    if (c === '\\') {
      i++;
      continue;
    }
    if (c === '"') return i;
  }
  return -1;
}

/** Index of the last char of the JSON value starting at `start`, or -1 if incomplete. */
function scanValue(s: string, start: number): number {
  const c = s[start];
  if (c === '"') return scanString(s, start);
  if (c === '{' || c === '[') {
    let depth = 0;
    for (let i = start; i < s.length; i++) {
      const ch = s[i];
      if (ch === '"') {
        const end = scanString(s, i);
        if (end === -1) return -1;
        i = end;
        continue;
      }
      if (ch === '{' || ch === '[') depth++;
      else if (ch === '}' || ch === ']') {
        depth--;
        if (depth === 0) return i;
      }
    }
    return -1;
  }
  // number / literal: complete once a delimiter follows it
  for (let i = start; i < s.length; i++) {
    if (/[,}\]\s]/.test(s[i]!)) return i - 1;
  }
  return -1;
}
