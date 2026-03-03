#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env.local"

if [[ ! -f "$ROOT_DIR/.env.local.example" ]]; then
  echo "Missing .env.local.example"
  exit 1
fi

cp "$ROOT_DIR/.env.local.example" "$ENV_FILE"

echo "Choose provider (openai/gemini) [openai]:"
read -r PROVIDER
PROVIDER="${PROVIDER:-openai}"
PROVIDER="$(echo "$PROVIDER" | tr '[:upper:]' '[:lower:]')"

if [[ "$PROVIDER" != "openai" && "$PROVIDER" != "gemini" ]]; then
  echo "Invalid provider: $PROVIDER"
  exit 1
fi

if [[ "$PROVIDER" == "openai" ]]; then
  echo "Enter a NEW OpenAI API key (input hidden):"
  read -r -s PROVIDER_KEY
  echo
else
  echo "Enter a NEW Gemini API key (input hidden):"
  read -r -s PROVIDER_KEY
  echo
fi

if [[ -z "$PROVIDER_KEY" ]]; then
  echo "No key entered."
  exit 1
fi

tmp_file="$(mktemp)"
awk -v provider="$PROVIDER" -v key="$PROVIDER_KEY" '{
  if ($0 ~ /^FLO_AI_PROVIDER=/) {
    print "FLO_AI_PROVIDER=" provider
  } else if ($0 ~ /^FLO_OPENAI_API_KEY=/) {
    if (provider == "openai") {
      print "FLO_OPENAI_API_KEY=" key
    } else {
      print "FLO_OPENAI_API_KEY="
    }
  } else if ($0 ~ /^FLO_GEMINI_API_KEY=/) {
    if (provider == "gemini") {
      print "FLO_GEMINI_API_KEY=" key
    } else {
      print "FLO_GEMINI_API_KEY="
    }
  } else {
    print $0
  }
}' "$ENV_FILE" > "$tmp_file"
mv "$tmp_file" "$ENV_FILE"

chmod 600 "$ENV_FILE"

echo "Wrote $ENV_FILE (permissions 600)."
echo "Now run: ./scripts/run_dev_app_bundle.sh"
