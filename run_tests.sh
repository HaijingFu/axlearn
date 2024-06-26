#!/usr/bin/env bash

set -e

# Install the package (necessary for CLI tests).
# Requirements should already be cached in the docker image.
pip install -e .

# Log installed versions
echo "PIP FREEZE:"
pip freeze

exit_if_error() {
  local exit_code=$1
  shift
  printf 'ERROR: %s\n' "$@" >&2
  exit "$exit_code"
}

download_assets() {
  mkdir -p axlearn/data/tokenizers/sentencepiece
  mkdir -p axlearn/data/tokenizers/bpe
  curl https://huggingface.co/t5-base/resolve/main/spiece.model -o axlearn/data/tokenizers/sentencepiece/t5-base
  curl https://huggingface.co/FacebookAI/roberta-base/raw/main/merges.txt -o axlearn/data/tokenizers/bpe/roberta-base-merges.txt
  curl https://huggingface.co/FacebookAI/roberta-base/raw/main/vocab.json -o axlearn/data/tokenizers/bpe/roberta-base-vocab.json
}

set -o xtrace
if [[ "${1:-x}" = "--skip-pre-commit" ]] ; then
  SKIP_PRECOMMIT=true
  shift
fi
UNQUOTED_PYTEST_FILES=$(echo $1 |  tr -d "'")

# Skip pre-commit on parallel CI because it is run as a separate job.
if [[ "${SKIP_PRECOMMIT:-false}" = "false" ]] ; then
  pre-commit install
  pre-commit run --all-files || exit_if_error $? "pre-commit failed."
  # Run pytype separately to utilize all cpus and for better output.
  pytype -j auto . || exit_if_error $? "pytype failed."
fi
download_assets
pytest --durations=10 -n auto -v -m "not (gs_login or tpu or high_cpu or fp64)" ${UNQUOTED_PYTEST_FILES} || exit_if_error $? "pytest failed."
JAX_ENABLE_X64=1 pytest -n auto -v -m "fp64" || exit_if_error $? "pytest failed."
