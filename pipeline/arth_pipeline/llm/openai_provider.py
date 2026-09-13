"""OpenAI implementation of LLMProvider: live chat completions and the Batch API."""

from __future__ import annotations

import io
import json
import logging
from typing import Any

from openai import BadRequestError, OpenAI

from .provider import BatchStatus, JsonRequest, JsonResult, Usage

log = logging.getLogger(__name__)


def _body(req: JsonRequest, *, with_temperature: bool = True) -> dict[str, Any]:
    body: dict[str, Any] = {
        "model": req.model,
        "messages": [{"role": "system", "content": req.system}, *req.messages],
        "response_format": {
            "type": "json_schema",
            "json_schema": {"name": req.schema_name, "strict": True, "schema": req.schema},
        },
        "max_completion_tokens": req.max_output_tokens,
    }
    if with_temperature and req.temperature is not None:
        body["temperature"] = req.temperature
    return body


def _usage(u: Any) -> Usage:
    if u is None:
        return Usage()
    # Works for both the SDK object (live) and the raw dict (batch output file).
    d = u if isinstance(u, dict) else u.model_dump()
    details = d.get("prompt_tokens_details") or {}
    return Usage(
        int(d.get("prompt_tokens") or 0),
        int(d.get("completion_tokens") or 0),
        int(details.get("cached_tokens") or 0),
    )


class OpenAIProvider:
    def __init__(self, api_key: str) -> None:
        if not api_key:
            raise RuntimeError("OPENAI_API_KEY is not set (pipeline/.env)")
        self._client = OpenAI(api_key=api_key)
        self._temperature_unsupported: set[str] = set()

    # ---- live ----

    def complete(self, req: JsonRequest) -> JsonResult:
        with_temp = req.model not in self._temperature_unsupported
        try:
            resp = self._client.chat.completions.create(**_body(req, with_temperature=with_temp))
        except BadRequestError as e:
            # Some model families reject `temperature`; drop it for that model and retry once.
            if with_temp and req.temperature is not None and "temperature" in str(e):
                log.warning("model %s rejects temperature; retrying without", req.model)
                self._temperature_unsupported.add(req.model)
                resp = self._client.chat.completions.create(**_body(req, with_temperature=False))
            else:
                return JsonResult(req.custom_id, req.model, None, error=str(e))
        choice = resp.choices[0]
        msg = choice.message
        refusal = getattr(msg, "refusal", None)
        return JsonResult(
            req.custom_id,
            resp.model or req.model,
            msg.content,
            usage=_usage(resp.usage),
            refusal=refusal,
            error=None if msg.content else f"empty content (finish_reason={choice.finish_reason})",
        )

    # ---- batch ----

    def submit_batch(self, reqs: list[JsonRequest], description: str) -> str:
        lines = [
            json.dumps(
                {
                    "custom_id": r.custom_id,
                    "method": "POST",
                    "url": "/v1/chat/completions",
                    "body": _body(r, with_temperature=r.model not in self._temperature_unsupported),
                },
                ensure_ascii=False,
            )
            for r in reqs
        ]
        payload = ("\n".join(lines) + "\n").encode("utf-8")
        uploaded = self._client.files.create(file=("batch.jsonl", io.BytesIO(payload)), purpose="batch")
        batch = self._client.batches.create(
            input_file_id=uploaded.id,
            endpoint="/v1/chat/completions",
            completion_window="24h",
            metadata={"description": description},
        )
        return batch.id

    def batch_status(self, batch_id: str) -> BatchStatus:
        b = self._client.batches.retrieve(batch_id)
        counts = b.request_counts
        return BatchStatus(
            id=b.id,
            status=b.status,
            total=counts.total if counts else 0,
            completed=counts.completed if counts else 0,
            failed=counts.failed if counts else 0,
            output_file_id=b.output_file_id,
            error_file_id=b.error_file_id,
        )

    def fetch_batch(self, batch_id: str) -> list[JsonResult]:
        status = self.batch_status(batch_id)
        results: list[JsonResult] = []
        for file_id, is_error in ((status.output_file_id, False), (status.error_file_id, True)):
            if not file_id:
                continue
            text = self._client.files.content(file_id).text
            for line in text.splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                cid = row["custom_id"]
                err = row.get("error")
                resp = row.get("response") or {}
                body = resp.get("body") or {}
                if is_error or err or resp.get("status_code", 200) != 200:
                    detail = json.dumps(err or body.get("error") or body)
                    results.append(JsonResult(cid, "", None, error=detail))
                    continue
                choice = (body.get("choices") or [{}])[0]
                msg = choice.get("message") or {}
                results.append(
                    JsonResult(
                        cid,
                        body.get("model", ""),
                        msg.get("content"),
                        usage=_usage(body.get("usage")),
                        refusal=msg.get("refusal"),
                        error=None
                        if msg.get("content")
                        else f"empty content ({choice.get('finish_reason')})",  # noqa: E501
                    )
                )
        return results
