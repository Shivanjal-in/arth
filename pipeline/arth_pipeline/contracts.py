"""Raw JSON Schemas and prompt assets from contracts/, loaded once."""

from __future__ import annotations

import json
from functools import cache
from typing import Any

from .config import CONTRACTS_DIR


@cache
def schema(name: str) -> dict[str, Any]:
    """`schema("entry-generation")` → the parsed JSON Schema, ready for Structured Outputs."""
    path = CONTRACTS_DIR / "schemas" / f"{name}.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    # OpenAI rejects unknown top-level keys; strip the metadata it doesn't want.
    return {k: v for k, v in data.items() if k not in ("$schema", "$id", "title")}


@cache
def prompt_examples() -> dict[str, Any]:
    return json.loads((CONTRACTS_DIR / "prompt-examples.json").read_text(encoding="utf-8"))


@cache
def prompt_text(name: str) -> str:
    return (CONTRACTS_DIR / "prompts" / f"{name}.md").read_text(encoding="utf-8").strip()
