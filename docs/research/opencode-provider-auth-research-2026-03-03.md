# OpenCode Provider/Auth Research (2026-03-03)

- Upstream repo: `https://github.com/sst/opencode`
- Audited commit: `48412f75ace87519b6550eea3b0c83e483a55297`
- Provider source files: `packages/opencode/src/provider/models.ts`, `packages/opencode/src/provider/provider.ts`, `packages/opencode/src/provider/auth.ts`
- Zen failover source: `packages/console/app/src/routes/zen/util/handler.ts`

## Key Findings

1. OpenCode does not hardcode a fixed provider list. It loads providers/models from `models.dev` (`https://models.dev/api.json`) at runtime and refreshes cache hourly.
2. OpenCode CLI stores one auth record per provider in `~/.local/share/opencode/auth.json` (API key or OAuth tokens).
3. OpenCode CLI supports provider/model selection, but cross-provider failover is implemented in OpenCode Zen routing logic, not in local CLI provider runtime.
4. Zen failover behavior includes weighted provider selection, sticky provider options, fallback provider routing, and 429 retry with exponential backoff.

## Runtime Inventory Snapshot

- Snapshot generated from models.dev: 2026-03-03T10:19:41.815Z
- Provider count: 97
- Model count: 3053
- Full inventory JSON: `docs/research/opencode-models-dev-providers-2026-03-03.json`

### Largest Provider Catalogs (Top 15 by model count)

- kilo: 263 models
- vercel: 200 models
- openrouter: 186 models
- poe: 114 models
- azure: 96 models
- amazon-bedrock: 95 models
- azure-cognitive-services: 95 models
- helicone: 91 models
- novita-ai: 84 models
- qiniu-ai: 76 models
- siliconflow-cn: 72 models
- nvidia: 71 models
- siliconflow: 70 models
- cloudflare-ai-gateway: 68 models
- chutes: 67 models

## OpenCode Provider Engine

### Bundled SDK adapters (from `BUNDLED_PROVIDERS`)

- @ai-sdk/amazon-bedrock
- @ai-sdk/anthropic
- @ai-sdk/azure
- @ai-sdk/google
- @ai-sdk/google-vertex
- @ai-sdk/google-vertex/anthropic
- @ai-sdk/openai
- @ai-sdk/openai-compatible
- @openrouter/ai-sdk-provider
- @ai-sdk/xai
- @ai-sdk/mistral
- @ai-sdk/groq
- @ai-sdk/deepinfra
- @ai-sdk/cerebras
- @ai-sdk/cohere
- @ai-sdk/gateway
- @ai-sdk/togetherai
- @ai-sdk/perplexity
- @ai-sdk/vercel
- @gitlab/gitlab-ai-provider
- @ai-sdk/github-copilot

### Special custom loaders (from `CUSTOM_LOADERS`)

- anthropic
- opencode
- openai
- github-copilot
- github-copilot-enterprise
- azure
- azure-cognitive-services
- amazon-bedrock
- openrouter
- vercel
- google-vertex
- google-vertex-anthropic
- sap-ai-core
- zenmux
- gitlab
- cloudflare-workers-ai
- cloudflare-ai-gateway
- cerebras
- kilo

### Provider assembly flow

1. Load provider/model metadata from models.dev.
2. Merge `opencode.json` provider overrides (env vars, options, model overrides, whitelist/blacklist).
3. Inject provider creds from environment and auth store.
4. Apply plugin auth loaders (including GitHub Copilot variants).
5. Apply custom loader logic and initialize SDKs lazily per provider+options hash.

## Zen Failover Mechanics

- Retry budget: `MAX_FAILOVER_RETRIES = 3` provider failovers + `MAX_429_RETRIES = 3` request retries.
- Provider selection precedence: BYOK provider -> trial provider -> sticky provider -> weighted provider -> fallback provider.
- Failover triggers: non-200 and not 404, sticky mode not strict, fallback provider exists, and current provider is not already fallback.
- 429 handling: exponential backoff (`500ms`, `1000ms`, `2000ms`) on the same provider request path.

## Provider IDs in Snapshot

- 302ai (64)
- abacus (55)
- aihubmix (43)
- alibaba (41)
- alibaba-cn (65)
- amazon-bedrock (95)
- anthropic (23)
- azure (96)
- azure-cognitive-services (95)
- bailing (2)
- baseten (9)
- berget (8)
- cerebras (4)
- chutes (67)
- cloudferro-sherlock (4)
- cloudflare-ai-gateway (68)
- cloudflare-workers-ai (39)
- cohere (12)
- cortecs (21)
- deepinfra (16)
- deepseek (2)
- evroc (13)
- fastrouter (14)
- fireworks-ai (13)
- firmware (16)
- friendli (7)
- github-copilot (22)
- github-models (55)
- gitlab (10)
- google (28)
- google-vertex (27)
- google-vertex-anthropic (11)
- groq (17)
- helicone (91)
- huggingface (20)
- iflowcn (14)
- inception (2)
- inference (9)
- io-net (17)
- jiekou (61)
- kilo (263)
- kimi-for-coding (2)
- kuae-cloud-coding-plan (1)
- llama (7)
- lmstudio (3)
- lucidquery (2)
- meganova (19)
- minimax (4)
- minimax-cn (4)
- minimax-cn-coding-plan (4)
- minimax-coding-plan (4)
- mistral (26)
- moark (2)
- modelscope (7)
- moonshotai (6)
- moonshotai-cn (6)
- morph (3)
- nano-gpt (33)
- nebius (46)
- nova (2)
- novita-ai (84)
- nvidia (71)
- ollama-cloud (33)
- openai (42)
- opencode (38)
- opencode-go (3)
- openrouter (186)
- ovhcloud (13)
- perplexity (4)
- poe (114)
- privatemode-ai (5)
- qihang-ai (9)
- qiniu-ai (76)
- requesty (20)
- sap-ai-core (22)
- scaleway (14)
- siliconflow (70)
- siliconflow-cn (72)
- stackit (8)
- stepfun (3)
- submodel (9)
- synthetic (26)
- togetherai (19)
- upstage (3)
- v0 (3)
- venice (36)
- vercel (200)
- vivgrid (8)
- vultr (5)
- wandb (10)
- xai (22)
- xiaomi (1)
- zai (9)
- zai-coding-plan (10)
- zenmux (67)
- zhipuai (9)
- zhipuai-coding-plan (9)
