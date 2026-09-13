#!/usr/bin/env sh
# Regenerate arth_pipeline/models from contracts/schemas. Never hand-edit the output.
set -e
cd "$(dirname "$0")"
.venv/bin/datamodel-codegen \
  --input ../contracts/schemas --input-file-type jsonschema \
  --output arth_pipeline/models --output-model-type pydantic_v2.BaseModel \
  --use-schema-description --field-constraints --disable-timestamp \
  --target-python-version 3.11 --formatters ruff-format 2>/dev/null
echo "models regenerated"
