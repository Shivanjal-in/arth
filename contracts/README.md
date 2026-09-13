# contracts/

Source of truth shared by `api/` (TypeScript), `pipeline/` (Python) and `app/` (Dart).
There is no shared package across the three languages, so this folder is it.

| File | What |
|---|---|
| `schemas/*.json` | JSON Schema (draft-07) for every wire/storage type. Written to also be valid OpenAI Structured Outputs schemas: every property listed in `required`, `additionalProperties: false`, refs only via `#/definitions`. |
| `normalize.md` | Text normalization rules, numbered. |
| `normalize-vectors.json` | Input/expected pairs for `normalizeSentence`, `normalizeWord` and the two cache-key functions. Each language's test suite loads this file. |
| `prompt-examples.json` | Gold examples of the Hindi register, shared by the pipeline and the API prompts. (Added in Phase 2.) |

Rules:

- Change a schema here, then regenerate: the Dart models are generated from these files, the Python side loads them into Pydantic, the API validates against them at runtime. Never hand-edit generated code.
- A vector change must be accompanied by all three implementations passing again.
