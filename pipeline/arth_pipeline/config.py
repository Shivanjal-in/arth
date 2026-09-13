"""All tunables in one place, read from the environment (.env via python-dotenv)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

PIPELINE_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = PIPELINE_DIR.parent
CONTRACTS_DIR = REPO_DIR / "contracts"
DATA_DIR = PIPELINE_DIR / "data"

load_dotenv(PIPELINE_DIR / ".env")


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


def read_wordlist(path: Path) -> list[str]:
    """One word per line; blank lines and '#' comments ignored."""
    out = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            out.append(line)
    return out


@dataclass(frozen=True)
class Pricing:
    """USD per 1M tokens, list price. Batch calls are billed at `batch_discount` × list."""

    input_per_m: float
    output_per_m: float
    cached_input_per_m: float


@dataclass(frozen=True)
class Config:
    openai_api_key: str = field(default_factory=lambda: _env("OPENAI_API_KEY", ""))
    mongodb_uri: str = field(default_factory=lambda: _env("MONGODB_URI", "mongodb://localhost:27017/arth"))

    model_top: str = field(default_factory=lambda: _env("LLM_MODEL_TOP", "gpt-5.6-terra"))
    model_tail: str = field(default_factory=lambda: _env("LLM_MODEL_TAIL", "gpt-5.6-luna"))
    top_tier_size: int = field(default_factory=lambda: int(_env("LLM_TOP_TIER_SIZE", "5000")))

    # Section 8 asks for 0.3, but the gpt-5.6 family rejects the parameter outright
    # (400: unsupported). Leave LLM_TEMPERATURE unset to omit it; set it for models that accept it.
    temperature: float | None = field(
        default_factory=lambda: float(_env("LLM_TEMPERATURE", "")) if _env("LLM_TEMPERATURE", "") else None
    )
    # Devanagari tokenizes ~2–3× worse than English; an entry with 8 senses can run long.
    max_output_tokens: int = 3000
    max_senses_per_entry: int = 8
    max_examples_per_sense: int = 2
    max_synonyms: int = 6
    batch_discount: float = 0.5

    def pricing(self, model: str) -> Pricing | None:
        inp = os.environ.get(f"PRICE_INPUT_{model}")
        out = os.environ.get(f"PRICE_OUTPUT_{model}")
        if inp is None or out is None:
            return None
        cached = os.environ.get(f"PRICE_CACHED_INPUT_{model}", str(float(inp) / 2))
        return Pricing(float(inp), float(out), float(cached))

    def model_for_tier(self, tier: str) -> str:
        return self.model_top if tier == "top" else self.model_tail


config = Config()


def read_jsonl(path: Path) -> list[dict]:
    """JSONL rows. Splits on '\\n' only: str.splitlines() also breaks on U+2028 and
    friends, which json.dumps leaves unescaped inside Hindi strings."""
    import json

    out = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            if line.strip():
                out.append(json.loads(line))
    return out
