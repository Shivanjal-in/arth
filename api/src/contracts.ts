/**
 * Loads the JSON Schemas from ../contracts/schemas and exposes compiled Ajv
 * validators. These are the same files the pipeline and the Dart codegen use;
 * nothing about the wire types is defined only in TypeScript.
 */
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Ajv, type ValidateFunction, type ErrorObject } from 'ajv';

/**
 * contracts/ sits at the repo root, beside api/. Walk up from this module so
 * the path works both from src/ (tsx) and from dist/src/ (compiled), or from
 * wherever CONTRACTS_DIR points.
 */
function findContractsDir(): string {
  if (process.env['CONTRACTS_DIR']) return process.env['CONTRACTS_DIR'];
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 6; i++) {
    const candidate = join(dir, 'contracts');
    if (existsSync(join(candidate, 'normalize.md'))) return candidate;
    dir = dirname(dir);
  }
  throw new Error('contracts/ directory not found; set CONTRACTS_DIR');
}

const contractsDir = findContractsDir() + '/';
const schemasDir = join(contractsDir, 'schemas') + '/';

function load(name: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(schemasDir, name), 'utf8')) as Record<string, unknown>;
}

export const schemas = {
  dictionaryEntry: load('dictionary-entry.json'),
  contextResult: load('context-result.json'),
  contextIndex: load('context-index.json'),
  entryGeneration: load('entry-generation.json'),
  translationResult: load('translation-result.json'),
  phraseMatch: load('phrase-match.json'),
  apiError: load('api-error.json'),
} as const;

/** System prompts shared with the pipeline, verbatim. */
export function promptText(name: 'context-system' | 'translate-system' | 'entry-system'): string {
  return readFileSync(`${contractsDir}prompts/${name}.md`, 'utf8').trim();
}

export type PromptExamples = {
  entry: { input: Record<string, unknown>; output: Record<string, unknown> }[];
  context: { input: Record<string, unknown>; output: ContextResult }[];
  translate: { input: Record<string, unknown>; output: TranslationResult }[];
};

let examples: PromptExamples | undefined;
export function promptExamples(): PromptExamples {
  examples ??= JSON.parse(readFileSync(`${contractsDir}prompt-examples.json`, 'utf8')) as PromptExamples;
  return examples;
}

/** JSON Schema stripped of the metadata OpenAI strict mode rejects. */
export function schemaForModel(name: keyof typeof schemas): Record<string, unknown> {
  const { $schema: _s, $id: _i, title: _t, ...rest } = schemas[name] as Record<string, unknown>;
  return rest;
}

const ajv = new Ajv({ allErrors: true, strict: true });
for (const s of Object.values(schemas)) ajv.addSchema(s);

function compile<T>(name: keyof typeof schemas): ValidateFunction<T> {
  return ajv.getSchema<T>(schemas[name]['$id'] as string) as ValidateFunction<T>;
}

export const validate = {
  dictionaryEntry: compile<DictionaryEntry>('dictionaryEntry'),
  contextResult: compile<ContextResult>('contextResult'),
  contextIndex: compile<{ senseIndex: number }>('contextIndex'),
  entryGeneration: compile<EntryGeneration>('entryGeneration'),
  translationResult: compile<TranslationResult>('translationResult'),
  phraseMatch: compile<PhraseMatch>('phraseMatch'),
};

export function formatErrors(errors: ErrorObject[] | null | undefined): string {
  return (errors ?? []).map((e) => `${e.instancePath || '/'} ${e.message ?? ''}`).join('; ');
}

// ---- TypeScript views of the contract types. Mirror contracts/schemas exactly. ----

export type BilingualPair = { en: string; hi: string };

export type Sense = {
  index: number;
  partOfSpeech: string;
  meaning: string;
  definition: string;
  examples: BilingualPair[];
};

export type Form = { en: string; label: string; hi: string };

export type DictionaryEntry = {
  word: string;
  ipa: string;
  hindiPronunciation: string;
  senses: Sense[];
  synonyms: BilingualPair[];
  antonyms: BilingualPair[];
  forms: Form[];
  isPhrase: boolean;
};

export type ContextResult = { senseIndex: number; meaning: string; note: string };

export type TranslationResult = {
  source: string;
  hindi: string;
  simpleMeaning: string;
  difficultWords: BilingualPair[];
};

export type PhraseMatch = { phrase: string; lemma: string; start: number; tokenCount: number };

/** The model's output for one headword: the Hindi layer only (contracts/schemas/entry-generation.json). */
export type EntryGeneration = {
  hindiPronunciation: string;
  senses: Sense[];
  synonyms: BilingualPair[];
  antonyms: BilingualPair[];
  forms: Form[];
};

/** What pipeline/03_extract.py produces per word and 08_stage.py stores. */
export type WiktionaryExtract = {
  word: string;
  ipa: string;
  isPhrase: boolean;
  senses: { index: number; partOfSpeech: string; gloss: string; examples: string[] }[];
  synonyms: string[];
  antonyms: string[];
  forms: { en: string; label: string }[];
};
