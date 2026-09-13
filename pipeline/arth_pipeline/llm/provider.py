"""The one interface every model call goes through. No SDK calls anywhere else."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class Usage:
    input_tokens: int = 0
    output_tokens: int = 0
    cached_input_tokens: int = 0

    def __add__(self, other: Usage) -> Usage:
        return Usage(
            self.input_tokens + other.input_tokens,
            self.output_tokens + other.output_tokens,
            self.cached_input_tokens + other.cached_input_tokens,
        )


@dataclass(frozen=True)
class JsonRequest:
    """One Structured-Outputs chat completion. `messages` excludes the system message."""

    custom_id: str
    model: str
    system: str
    messages: list[dict[str, str]]
    schema_name: str
    schema: dict[str, Any]
    temperature: float | None = None  # None = don't send the parameter
    max_output_tokens: int = 2000


@dataclass
class JsonResult:
    custom_id: str
    model: str
    content: str | None
    usage: Usage = field(default_factory=Usage)
    error: str | None = None
    refusal: str | None = None


@dataclass(frozen=True)
class BatchStatus:
    id: str
    status: str  # validating | in_progress | finalizing | completed | failed | expired | cancelled
    total: int
    completed: int
    failed: int
    output_file_id: str | None
    error_file_id: str | None

    @property
    def done(self) -> bool:
        return self.status in ("completed", "failed", "expired", "cancelled")


class LLMProvider(Protocol):
    def complete(self, req: JsonRequest) -> JsonResult: ...

    def submit_batch(self, reqs: list[JsonRequest], description: str) -> str:
        """Upload a JSONL batch, return the batch id."""
        ...

    def batch_status(self, batch_id: str) -> BatchStatus: ...

    def fetch_batch(self, batch_id: str) -> list[JsonResult]: ...
