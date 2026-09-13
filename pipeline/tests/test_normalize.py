import json
from pathlib import Path

import pytest

from arth_pipeline.normalize import context_key, normalize_sentence, normalize_word, sentence_key

VECTORS = Path(__file__).resolve().parents[2] / "contracts" / "normalize-vectors.json"
_vectors = json.loads(VECTORS.read_text(encoding="utf-8"))["vectors"]

assert len(_vectors) >= 40, "vector file looks truncated"


@pytest.mark.parametrize("v", _vectors, ids=[v["id"] for v in _vectors])
def test_vector(v: dict) -> None:
    kind = v["kind"]
    if kind == "sentence":
        assert normalize_sentence(v["input"]) == v["expected"]
    elif kind == "word":
        assert normalize_word(v["input"]) == v["expected"]
    elif kind == "key" and v["keyKind"] == "context":
        assert context_key(v["word"], v["sentence"]) == v["expected"]
    elif kind == "key" and v["keyKind"] == "sentence":
        assert sentence_key(v["text"]) == v["expected"]
    else:
        pytest.fail(f"unknown vector kind {kind}")
