"""Scripted provider for tests: returns canned content per custom_id, in order, and records requests."""

from __future__ import annotations

from collections import defaultdict

from .provider import BatchStatus, JsonRequest, JsonResult, Usage


class FakeProvider:
    def __init__(self, scripted: dict[str, list[str | None]]) -> None:
        self._scripted = {k: list(v) for k, v in scripted.items()}
        self.requests: list[JsonRequest] = []
        self.calls: dict[str, int] = defaultdict(int)

    def _next(self, req: JsonRequest) -> JsonResult:
        self.requests.append(req)
        self.calls[req.custom_id] += 1
        queue = self._scripted.get(req.custom_id, [])
        content = queue.pop(0) if queue else None
        return JsonResult(
            req.custom_id,
            req.model,
            content,
            usage=Usage(100, 50, 0),
            error=None if content else "scripted empty",
        )

    def complete(self, req: JsonRequest) -> JsonResult:
        return self._next(req)

    def submit_batch(self, reqs: list[JsonRequest], description: str) -> str:
        self._pending = [self._next(r) for r in reqs]
        return "batch_fake"

    def batch_status(self, batch_id: str) -> BatchStatus:
        n = len(self._pending)
        return BatchStatus(batch_id, "completed", n, n, 0, "out", None)

    def fetch_batch(self, batch_id: str) -> list[JsonResult]:
        return list(self._pending)
