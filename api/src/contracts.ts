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
  translationResult: load('translation-result.json'),
  phraseMatch: load('phrase-match.json'),
  apiError: load('api-error.json'),
} as const;

const ajv = new Ajv({ allErrors: true, strict: true });
for (const s of Object.values(schemas)) ajv.addSchema(s);

function compile<T>(name: keyof typeof schemas): ValidateFunction<T> {
  return ajv.getSchema<T>(schemas[name]['$id'] as string) as ValidateFunction<T>;
}

export const validate = {
  dictionaryEntry: compile<DictionaryEntry>('dictionaryEntry'),
  contextResult: compile<ContextResult>('contextResult'),
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

export type PhraseMatch = { phrase: string; lemma: string };
