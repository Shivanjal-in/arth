import json
import re
from collections.abc import Callable

import pytest

from arth_pipeline.contracts import prompt_examples, schema
from arth_pipeline.generate import (
    EntryValidationError,
    build_request,
    generate_live,
    parse_generation,
    settle_batch,
)
from arth_pipeline.llm.fake_provider import FakeProvider
from arth_pipeline.models.dictionary_entry import DictionaryEntry

# The gold examples double as fixtures: their inputs are exactly what 03_extract emits.
GOLD = prompt_examples()["entry"]


def gold(word: str) -> tuple[dict, dict]:
    ex = next(e for e in GOLD if e["input"]["word"] == word)
    return ex["input"], ex["output"]


def test_gold_examples_validate_against_contract() -> None:
    for ex in GOLD:
        entry = parse_generation(ex["input"], json.dumps(ex["output"], ensure_ascii=False))
        assert isinstance(entry, DictionaryEntry)
        assert entry.word == ex["input"]["word"]
        assert [s.index for s in entry.senses] == list(range(len(ex["input"]["senses"])))


def test_schema_is_structured_outputs_compatible() -> None:
    s = schema("entry-generation")
    assert s["additionalProperties"] is False
    assert set(s["required"]) == set(s["properties"])
    for d in s["definitions"].values():
        assert d["additionalProperties"] is False
        assert set(d["required"]) == set(d["properties"])
    assert "$schema" not in s and "$id" not in s


def test_request_has_fixed_prefix_then_word() -> None:
    inp, _ = gold("fortune")
    req = build_request(inp, "model-x")
    assert req.messages[-1]["role"] == "user"
    assert json.loads(req.messages[-1]["content"])["word"] == "fortune"
    assert len(req.messages) == 2 * len(GOLD) + 1
    assert req.schema_name == "entry_generation"


@pytest.mark.parametrize(
    "mutate, fragment",
    [
        (lambda o: o["senses"].pop(), "expected 3 senses"),
        (lambda o: o["senses"][0].__setitem__("index", 7), "index"),
        (lambda o: o["senses"][0].__setitem__("meaning", "wealth"), "no Devanagari"),
        (lambda o: o["senses"][0].__setitem__("definition", "बहुत सारा money"), "English word"),
        (lambda o: o["synonyms"].pop(), "synonyms: en list"),
        (lambda o: o["forms"][0].__setitem__("label", "plural"), "forms: (en, label)"),
        (lambda o: o.__setitem__("hindiPronunciation", ""), "empty"),
        (lambda o: o.__setitem__("extra", 1), "schema"),
    ],
)
def test_cross_checks_reject_bad_output(mutate: Callable[[dict], object], fragment: str) -> None:
    inp, out = gold("fortune")
    bad = json.loads(json.dumps(out))
    mutate(bad)
    with pytest.raises(EntryValidationError, match=re.escape(fragment)):
        parse_generation(inp, json.dumps(bad, ensure_ascii=False))


def test_pos_mismatch_is_overwritten_not_fatal() -> None:
    inp, out = gold("fortune")
    bad = json.loads(json.dumps(out))
    bad["senses"][0]["partOfSpeech"] = "क्रिया"
    entry = parse_generation(inp, json.dumps(bad, ensure_ascii=False))
    assert entry.senses[0].partOfSpeech == "संज्ञा"


def test_retry_once_then_succeed() -> None:
    inp, out = gold("fortune")
    bad = json.loads(json.dumps(out))
    bad["senses"].pop()
    provider = FakeProvider(
        {"fortune": [json.dumps(bad, ensure_ascii=False), json.dumps(out, ensure_ascii=False)]}
    )
    [o] = generate_live(provider, [inp], lambda x: "model-x")
    assert o.entry is not None and o.attempts == 2 and o.error is None
    assert provider.calls["fortune"] == 2
    retry = provider.requests[1]
    assert retry.messages[-2]["role"] == "assistant"
    assert "failed validation" in retry.messages[-1]["content"]
    assert "expected 3 senses" in retry.messages[-1]["content"]
    assert o.usage.input_tokens == 200  # both attempts counted


def test_second_failure_is_skipped_and_logged(caplog: pytest.LogCaptureFixture) -> None:
    inp, out = gold("fortune")
    bad = json.loads(json.dumps(out))
    bad["senses"][0]["meaning"] = "wealth"
    provider = FakeProvider(
        {"fortune": [json.dumps(bad, ensure_ascii=False), json.dumps(bad, ensure_ascii=False)]}
    )
    [o] = generate_live(provider, [inp], lambda x: "model-x")
    assert o.entry is None and o.attempts == 2
    assert "no Devanagari" in (o.error or "")
    assert provider.calls["fortune"] == 2
    assert any("skipped" in r.message for r in caplog.records)


def test_empty_content_counts_as_failure() -> None:
    inp, out = gold("single")
    provider = FakeProvider({"single": [None, json.dumps(out, ensure_ascii=False)]})
    [o] = generate_live(provider, [inp], lambda x: "model-x")
    assert o.entry is not None and o.attempts == 2


def test_batch_results_settle_and_retry_live() -> None:
    f_in, f_out = gold("fortune")
    s_in, s_out = gold("single")
    bad = json.loads(json.dumps(s_out))
    bad["forms"].pop()
    provider = FakeProvider(
        {
            "fortune": [json.dumps(f_out, ensure_ascii=False)],
            "single": [json.dumps(bad, ensure_ascii=False), json.dumps(s_out, ensure_ascii=False)],
        }
    )
    reqs = [build_request(x, "model-x") for x in (f_in, s_in)]
    batch_id = provider.submit_batch(reqs, "test")
    results = provider.fetch_batch(batch_id)
    outcomes = settle_batch(provider, [f_in, s_in], results, lambda x: "model-x")
    assert [o.attempts for o in outcomes] == [1, 2]
    assert all(o.entry for o in outcomes) and all(o.batch for o in outcomes)
