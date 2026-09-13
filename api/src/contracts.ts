/**
 * Loads the JSON Schemas from ../contracts/schemas and exposes compiled Ajv
 * validators. These are the same files the pipeline and the Dart codegen use;
 * nothing about the wire types is defined only in TypeScript.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { Ajv, type ValidateFunction, type ErrorObject } from 'ajv';

const schemasDir = fileURLToPath(new URL('../../contracts/schemas/', import.meta.url));

function load(name: string): Record<string, unknown> {
  return JSON.parse(readFileSync(new URL(name, `file://${schemasDir}`), 'utf8')) as Record<string, unknown>;
}

export const schemas = {
  dictionaryEntry: load('dictionary-entry.json'),
  contextResult: load('context-result.json'),
  contextIndex: load('context-index.json'),
  translationResult: load('translation-result.json'),
  phraseMatch: load('phrase-match.json'),
  apiError: load('api-error.json'),
} as const;

const contractsDir = fileURLToPath(new URL('../../contracts/', import.meta.url));

/** System prompts shared with the pipeline, verbatim. */
export function promptText(name: 'context-system' | 'translate-system'): string {
  return readFileSync(`${contractsDir}prompts/${name}.md`, 'utf8').trim();
}

export type PromptExamples = {
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
