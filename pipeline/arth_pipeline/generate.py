"""Turn extracted Wiktionary entries into DictionaryEntry via the LLM.

Prompt = fixed prefix (system + gold examples from contracts/) + one user message
per word, so OpenAI prompt caching applies across the run. Output is parsed
against the generated Pydantic model, then cross-checked against the input
(sense count, indexes, POS, the en side of synonyms/antonyms/forms) and for
Latin letters in Hindi fields. One retry with the error appended; then skip.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from typing import Any

from pydantic import ValidationError

from .config import config
from .contracts import prompt_examples, prompt_text, schema
from .llm.provider import JsonRequest, JsonResult, LLMProvider, Usage
from .models.dictionary_entry import DictionaryEntry
from .models.entry_generation import EntryGeneration

log = logging.getLogger(__name__)

# A real English word leaking into Hindi prose. Single letters (x, f, "the letter O")
# and short tokens are legitimate in definitions and examples.
_LATIN_WORD = re.compile(r"[A-Za-z]{3,}")
_DEVANAGARI = re.compile("[" + chr(0x0900) + "-" + chr(0x097F) + "]")  # Devanagari block


class EntryValidationError(Exception):
    pass


# ---- prompt ----


def user_message(extract: dict[str, Any]) -> str:
    """The exact JSON the gold examples use, so the model sees a consistent shape."""
    payload = {
        "word": extract["word"],
        "ipa": extract.get("ipa", ""),
        "isPhrase": bool(extract.get("isPhrase")),
        "senses": [
            {
                "index": s["index"],
                "partOfSpeech": s["partOfSpeech"],
                "gloss": s["gloss"],
                "examples": s.get("examples", []),
            }
            for s in extract["senses"]
        ],
        "synonyms": extract.get("synonyms", []),
        "antonyms": extract.get("antonyms", []),
        "forms": [{"en": f["en"], "label": f["label"]} for f in extract.get("forms", [])],
    }
    return json.dumps(payload, ensure_ascii=False)


def prefix_messages() -> list[dict[str, str]]:
    msgs: list[dict[str, str]] = []
    for ex in prompt_examples()["entry"]:
        msgs.append({"role": "user", "content": json.dumps(ex["input"], ensure_ascii=False)})
        msgs.append({"role": "assistant", "content": json.dumps(ex["output"], ensure_ascii=False)})
    return msgs


def build_request(extract: dict[str, Any], model: str, custom_id: str | None = None) -> JsonRequest:
    return JsonRequest(
        custom_id=custom_id or extract["word"],
        model=model,
        system=prompt_text("entry-system"),
        messages=[*prefix_messages(), {"role": "user", "content": user_message(extract)}],
        schema_name="entry_generation",
        schema=schema("entry-generation"),
        temperature=config.temperature,
        max_output_tokens=config.max_output_tokens,
    )


def retry_request(base: JsonRequest, bad_content: str, error: str) -> JsonRequest:
    """Same prefix, plus the failed answer and the validation error, so the fix is cheap and cached."""
    return JsonRequest(
        custom_id=base.custom_id,
        model=base.model,
        system=base.system,
        messages=[
            *base.messages,
            {"role": "assistant", "content": bad_content},
            {
                "role": "user",
                "content": (
                    "That answer failed validation:\n"
                    + error
                    + "\nReturn the corrected JSON for the same word. Keep every sense, in order, "
                    "with the same index and partOfSpeech; keep every en value exactly as given."
                ),
            },
        ],
        schema_name=base.schema_name,
        schema=base.schema,
        temperature=base.temperature,
        max_output_tokens=base.max_output_tokens,
    )


# ---- validation ----


def _check_hindi(path: str, value: str, errors: list[str], *, allow_latin: bool = False) -> None:
    if not value.strip():
        errors.append(f"{path}: empty")
    elif not _DEVANAGARI.search(value):
        errors.append(f"{path}: no Devanagari in {value!r}")
    elif not allow_latin and _LATIN_WORD.search(value):
        errors.append(f"{path}: English word in Hindi field {value!r}")


def parse_generation(extract: dict[str, Any], content: str) -> DictionaryEntry:
    """Parse the model output and merge with the Wiktionary side. Raises EntryValidationError."""
    try:
        gen = EntryGeneration.model_validate_json(content)
    except ValidationError as e:
        raise EntryValidationError(f"schema: {e.errors(include_url=False)[:5]}") from e

    errors: list[str] = []
    want = extract["senses"]
    if len(gen.senses) != len(want):
        errors.append(f"senses: expected {len(want)} senses, got {len(gen.senses)}")
    for i, (got, exp) in enumerate(zip(gen.senses, want, strict=False)):
        if got.index != exp["index"]:
            errors.append(f"senses[{i}].index: expected {exp['index']}, got {got.index}")
        if got.partOfSpeech != exp["partOfSpeech"]:
            # Not fatal: we trust our own POS mapping and overwrite.
            log.debug("%s sense %d: POS %r → %r", extract["word"], i, got.partOfSpeech, exp["partOfSpeech"])
            got.partOfSpeech = exp["partOfSpeech"]
        _check_hindi(f"senses[{i}].meaning", got.meaning, errors)
        _check_hindi(f"senses[{i}].definition", got.definition, errors)
        for j, ex in enumerate(got.examples):
            _check_hindi(f"senses[{i}].examples[{j}].hi", ex.hi, errors, allow_latin=True)
            if not ex.en.strip():
                errors.append(f"senses[{i}].examples[{j}].en: empty")

    for key in ("synonyms", "antonyms"):
        got_en = [p.en for p in getattr(gen, key)]
        exp_en = list(extract.get(key, []))
        if got_en != exp_en:
            errors.append(f"{key}: en list must be exactly {exp_en}, got {got_en}")
        for j, p in enumerate(getattr(gen, key)):
            _check_hindi(f"{key}[{j}].hi", p.hi, errors, allow_latin=True)

    got_forms = [(f.en, f.label) for f in gen.forms]
    exp_forms = [(f["en"], f["label"]) for f in extract.get("forms", [])]
    if got_forms != exp_forms:
        errors.append(f"forms: (en, label) pairs must be exactly {exp_forms}, got {got_forms}")
    for j, f in enumerate(gen.forms):
        _check_hindi(f"forms[{j}].hi", f.hi, errors, allow_latin=True)

    _check_hindi("hindiPronunciation", gen.hindiPronunciation, errors)

    if errors:
        raise EntryValidationError("; ".join(errors[:8]))

    return DictionaryEntry.model_validate(
        {
            "word": extract["word"],
            "ipa": extract.get("ipa", ""),
            "hindiPronunciation": gen.hindiPronunciation,
            "senses": [s.model_dump() for s in gen.senses],
            "synonyms": [p.model_dump() for p in gen.synonyms],
            "antonyms": [p.model_dump() for p in gen.antonyms],
            "forms": [f.model_dump() for f in gen.forms],
            "isPhrase": bool(extract.get("isPhrase")),
        }
    )


# ---- orchestration ----


@dataclass
class Outcome:
    word: str
    entry: DictionaryEntry | None
    model: str
    attempts: int
    usage: Usage = field(default_factory=Usage)
    error: str | None = None
    batch: bool = False


def _settle(
    extract: dict[str, Any], req: JsonRequest, result: JsonResult, provider: LLMProvider, *, batch: bool
) -> Outcome:
    """Validate one result; on failure retry once live with the error appended."""
    usage = result.usage
    model = result.model or req.model
    if result.error or not result.content:
        first_error = result.error or "empty content"
    else:
        try:
            entry = parse_generation(extract, result.content)
            return Outcome(extract["word"], entry, model, 1, usage, batch=batch)
        except EntryValidationError as e:
            first_error = str(e)

    log.warning("%s: attempt 1 failed: %s", extract["word"], first_error[:300])
    retry = retry_request(req, result.content or "{}", first_error)
    second = provider.complete(retry)
    usage = usage + second.usage
    if second.error or not second.content:
        err = f"attempt 2: {second.error or 'empty content'}"
        log.error("%s: skipped — %s", extract["word"], err)
        return Outcome(extract["word"], None, model, 2, usage, error=f"{first_error} || {err}", batch=batch)
    try:
        entry = parse_generation(extract, second.content)
        return Outcome(extract["word"], entry, model, 2, usage, batch=batch)
    except EntryValidationError as e:
        log.error("%s: skipped — attempt 2 failed: %s", extract["word"], str(e)[:300])
        return Outcome(extract["word"], None, model, 2, usage, error=f"{first_error} || {e}", batch=batch)


def generate_live(provider: LLMProvider, extracts: list[dict[str, Any]], model_for: Any) -> list[Outcome]:
    out: list[Outcome] = []
    for x in extracts:
        req = build_request(x, model_for(x))
        out.append(_settle(x, req, provider.complete(req), provider, batch=False))
    return out


def settle_batch(
    provider: LLMProvider, extracts: list[dict[str, Any]], results: list[JsonResult], model_for: Any
) -> list[Outcome]:
    by_id = {r.custom_id: r for r in results}
    out: list[Outcome] = []
    for x in extracts:
        req = build_request(x, model_for(x))
        res = by_id.get(req.custom_id) or JsonResult(
            req.custom_id, req.model, None, error="missing from batch"
        )
        out.append(_settle(x, req, res, provider, batch=True))
    return out


# ---- cost ----


def cost_usd(model: str, usage: Usage, *, batch: bool) -> float | None:
    p = config.pricing(model)
    if p is None:
        return None
    uncached = max(0, usage.input_tokens - usage.cached_input_tokens)
    usd = (
        uncached * p.input_per_m
        + usage.cached_input_tokens * p.cached_input_per_m
        + usage.output_tokens * p.output_per_m
    ) / 1_000_000
    return usd * (config.batch_discount if batch else 1.0)
