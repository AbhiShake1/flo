import Foundation

public struct ProviderCatalogEntry: Sendable {
    public let id: String
    public let displayName: String
    public let legacyEnvKeys: [String]
    public let apiBaseURL: String?

    public init(id: String, displayName: String, legacyEnvKeys: [String], apiBaseURL: String?) {
        self.id = id
        self.displayName = displayName
        self.legacyEnvKeys = legacyEnvKeys
        self.apiBaseURL = apiBaseURL
    }
}

public enum ProviderCatalog {
    public static let allEntries: [ProviderCatalogEntry] = [
        ProviderCatalogEntry(
            id: "302ai",
            displayName: "302.AI",
            legacyEnvKeys: ["302AI_API_KEY"],
            apiBaseURL: "https://api.302.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "abacus",
            displayName: "Abacus",
            legacyEnvKeys: ["ABACUS_API_KEY"],
            apiBaseURL: "https://routellm.abacus.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "aihubmix",
            displayName: "AIHubMix",
            legacyEnvKeys: ["AIHUBMIX_API_KEY"],
            apiBaseURL: "https://aihubmix.com/v1"
        ),
        ProviderCatalogEntry(
            id: "alibaba",
            displayName: "Alibaba",
            legacyEnvKeys: ["DASHSCOPE_API_KEY"],
            apiBaseURL: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        ),
        ProviderCatalogEntry(
            id: "alibaba-cn",
            displayName: "Alibaba (China)",
            legacyEnvKeys: ["DASHSCOPE_API_KEY"],
            apiBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        ),
        ProviderCatalogEntry(
            id: "amazon-bedrock",
            displayName: "Amazon Bedrock",
            legacyEnvKeys: ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_REGION"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "anthropic",
            displayName: "Anthropic",
            legacyEnvKeys: ["ANTHROPIC_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "azure",
            displayName: "Azure",
            legacyEnvKeys: ["AZURE_RESOURCE_NAME", "AZURE_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "azure-cognitive-services",
            displayName: "Azure Cognitive Services",
            legacyEnvKeys: ["AZURE_COGNITIVE_SERVICES_RESOURCE_NAME", "AZURE_COGNITIVE_SERVICES_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "bailing",
            displayName: "Bailing",
            legacyEnvKeys: ["BAILING_API_TOKEN"],
            apiBaseURL: "https://api.tbox.cn/api/llm/v1/chat/completions"
        ),
        ProviderCatalogEntry(
            id: "baseten",
            displayName: "Baseten",
            legacyEnvKeys: ["BASETEN_API_KEY"],
            apiBaseURL: "https://inference.baseten.co/v1"
        ),
        ProviderCatalogEntry(
            id: "berget",
            displayName: "Berget.AI",
            legacyEnvKeys: ["BERGET_API_KEY"],
            apiBaseURL: "https://api.berget.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "cerebras",
            displayName: "Cerebras",
            legacyEnvKeys: ["CEREBRAS_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "chutes",
            displayName: "Chutes",
            legacyEnvKeys: ["CHUTES_API_KEY"],
            apiBaseURL: "https://llm.chutes.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "cloudferro-sherlock",
            displayName: "CloudFerro Sherlock",
            legacyEnvKeys: ["CLOUDFERRO_SHERLOCK_API_KEY"],
            apiBaseURL: "https://api-sherlock.cloudferro.com/openai/v1/"
        ),
        ProviderCatalogEntry(
            id: "cloudflare-ai-gateway",
            displayName: "Cloudflare AI Gateway",
            legacyEnvKeys: ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_GATEWAY_ID"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "cloudflare-workers-ai",
            displayName: "Cloudflare Workers AI",
            legacyEnvKeys: ["CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_API_KEY"],
            apiBaseURL: "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/ai/v1"
        ),
        ProviderCatalogEntry(
            id: "cohere",
            displayName: "Cohere",
            legacyEnvKeys: ["COHERE_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "cortecs",
            displayName: "Cortecs",
            legacyEnvKeys: ["CORTECS_API_KEY"],
            apiBaseURL: "https://api.cortecs.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "deepinfra",
            displayName: "Deep Infra",
            legacyEnvKeys: ["DEEPINFRA_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "deepseek",
            displayName: "DeepSeek",
            legacyEnvKeys: ["DEEPSEEK_API_KEY"],
            apiBaseURL: "https://api.deepseek.com"
        ),
        ProviderCatalogEntry(
            id: "evroc",
            displayName: "evroc",
            legacyEnvKeys: ["EVROC_API_KEY"],
            apiBaseURL: "https://models.think.evroc.com/v1"
        ),
        ProviderCatalogEntry(
            id: "fastrouter",
            displayName: "FastRouter",
            legacyEnvKeys: ["FASTROUTER_API_KEY"],
            apiBaseURL: "https://go.fastrouter.ai/api/v1"
        ),
        ProviderCatalogEntry(
            id: "fireworks-ai",
            displayName: "Fireworks AI",
            legacyEnvKeys: ["FIREWORKS_API_KEY"],
            apiBaseURL: "https://api.fireworks.ai/inference/v1/"
        ),
        ProviderCatalogEntry(
            id: "firmware",
            displayName: "Firmware",
            legacyEnvKeys: ["FIRMWARE_API_KEY"],
            apiBaseURL: "https://app.firmware.ai/api/v1"
        ),
        ProviderCatalogEntry(
            id: "friendli",
            displayName: "Friendli",
            legacyEnvKeys: ["FRIENDLI_TOKEN"],
            apiBaseURL: "https://api.friendli.ai/serverless/v1"
        ),
        ProviderCatalogEntry(
            id: "github-copilot",
            displayName: "GitHub Copilot",
            legacyEnvKeys: ["GITHUB_TOKEN"],
            apiBaseURL: "https://api.githubcopilot.com"
        ),
        ProviderCatalogEntry(
            id: "github-models",
            displayName: "GitHub Models",
            legacyEnvKeys: ["GITHUB_TOKEN"],
            apiBaseURL: "https://models.github.ai/inference"
        ),
        ProviderCatalogEntry(
            id: "gitlab",
            displayName: "GitLab Duo",
            legacyEnvKeys: ["GITLAB_TOKEN"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "google",
            displayName: "Google",
            legacyEnvKeys: ["GOOGLE_GENERATIVE_AI_API_KEY", "GEMINI_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "google-vertex",
            displayName: "Vertex",
            legacyEnvKeys: ["GOOGLE_VERTEX_PROJECT", "GOOGLE_VERTEX_LOCATION", "GOOGLE_APPLICATION_CREDENTIALS"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "google-vertex-anthropic",
            displayName: "Vertex (Anthropic)",
            legacyEnvKeys: ["GOOGLE_VERTEX_PROJECT", "GOOGLE_VERTEX_LOCATION", "GOOGLE_APPLICATION_CREDENTIALS"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "groq",
            displayName: "Groq",
            legacyEnvKeys: ["GROQ_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "helicone",
            displayName: "Helicone",
            legacyEnvKeys: ["HELICONE_API_KEY"],
            apiBaseURL: "https://ai-gateway.helicone.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "huggingface",
            displayName: "Hugging Face",
            legacyEnvKeys: ["HF_TOKEN"],
            apiBaseURL: "https://router.huggingface.co/v1"
        ),
        ProviderCatalogEntry(
            id: "iflowcn",
            displayName: "iFlow",
            legacyEnvKeys: ["IFLOW_API_KEY"],
            apiBaseURL: "https://apis.iflow.cn/v1"
        ),
        ProviderCatalogEntry(
            id: "inception",
            displayName: "Inception",
            legacyEnvKeys: ["INCEPTION_API_KEY"],
            apiBaseURL: "https://api.inceptionlabs.ai/v1/"
        ),
        ProviderCatalogEntry(
            id: "inference",
            displayName: "Inference",
            legacyEnvKeys: ["INFERENCE_API_KEY"],
            apiBaseURL: "https://inference.net/v1"
        ),
        ProviderCatalogEntry(
            id: "io-net",
            displayName: "IO.NET",
            legacyEnvKeys: ["IOINTELLIGENCE_API_KEY"],
            apiBaseURL: "https://api.intelligence.io.solutions/api/v1"
        ),
        ProviderCatalogEntry(
            id: "jiekou",
            displayName: "Jiekou.AI",
            legacyEnvKeys: ["JIEKOU_API_KEY"],
            apiBaseURL: "https://api.jiekou.ai/openai"
        ),
        ProviderCatalogEntry(
            id: "kilo",
            displayName: "Kilo Gateway",
            legacyEnvKeys: ["KILO_API_KEY"],
            apiBaseURL: "https://api.kilo.ai/api/gateway"
        ),
        ProviderCatalogEntry(
            id: "kimi-for-coding",
            displayName: "Kimi For Coding",
            legacyEnvKeys: ["KIMI_API_KEY"],
            apiBaseURL: "https://api.kimi.com/coding/v1"
        ),
        ProviderCatalogEntry(
            id: "kuae-cloud-coding-plan",
            displayName: "KUAE Cloud Coding Plan",
            legacyEnvKeys: ["KUAE_API_KEY"],
            apiBaseURL: "https://coding-plan-endpoint.kuaecloud.net/v1"
        ),
        ProviderCatalogEntry(
            id: "llama",
            displayName: "Llama",
            legacyEnvKeys: ["LLAMA_API_KEY"],
            apiBaseURL: "https://api.llama.com/compat/v1/"
        ),
        ProviderCatalogEntry(
            id: "lmstudio",
            displayName: "LMStudio",
            legacyEnvKeys: ["LMSTUDIO_API_KEY"],
            apiBaseURL: "http://127.0.0.1:1234/v1"
        ),
        ProviderCatalogEntry(
            id: "lucidquery",
            displayName: "LucidQuery AI",
            legacyEnvKeys: ["LUCIDQUERY_API_KEY"],
            apiBaseURL: "https://lucidquery.com/api/v1"
        ),
        ProviderCatalogEntry(
            id: "meganova",
            displayName: "Meganova",
            legacyEnvKeys: ["MEGANOVA_API_KEY"],
            apiBaseURL: "https://api.meganova.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "minimax",
            displayName: "MiniMax (minimax.io)",
            legacyEnvKeys: ["MINIMAX_API_KEY"],
            apiBaseURL: "https://api.minimax.io/anthropic/v1"
        ),
        ProviderCatalogEntry(
            id: "minimax-cn",
            displayName: "MiniMax (minimaxi.com)",
            legacyEnvKeys: ["MINIMAX_API_KEY"],
            apiBaseURL: "https://api.minimaxi.com/anthropic/v1"
        ),
        ProviderCatalogEntry(
            id: "minimax-cn-coding-plan",
            displayName: "MiniMax Coding Plan (minimaxi.com)",
            legacyEnvKeys: ["MINIMAX_API_KEY"],
            apiBaseURL: "https://api.minimaxi.com/anthropic/v1"
        ),
        ProviderCatalogEntry(
            id: "minimax-coding-plan",
            displayName: "MiniMax Coding Plan (minimax.io)",
            legacyEnvKeys: ["MINIMAX_API_KEY"],
            apiBaseURL: "https://api.minimax.io/anthropic/v1"
        ),
        ProviderCatalogEntry(
            id: "mistral",
            displayName: "Mistral",
            legacyEnvKeys: ["MISTRAL_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "moark",
            displayName: "Moark",
            legacyEnvKeys: ["MOARK_API_KEY"],
            apiBaseURL: "https://moark.com/v1"
        ),
        ProviderCatalogEntry(
            id: "modelscope",
            displayName: "ModelScope",
            legacyEnvKeys: ["MODELSCOPE_API_KEY"],
            apiBaseURL: "https://api-inference.modelscope.cn/v1"
        ),
        ProviderCatalogEntry(
            id: "moonshotai",
            displayName: "Moonshot AI",
            legacyEnvKeys: ["MOONSHOT_API_KEY"],
            apiBaseURL: "https://api.moonshot.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "moonshotai-cn",
            displayName: "Moonshot AI (China)",
            legacyEnvKeys: ["MOONSHOT_API_KEY"],
            apiBaseURL: "https://api.moonshot.cn/v1"
        ),
        ProviderCatalogEntry(
            id: "morph",
            displayName: "Morph",
            legacyEnvKeys: ["MORPH_API_KEY"],
            apiBaseURL: "https://api.morphllm.com/v1"
        ),
        ProviderCatalogEntry(
            id: "nano-gpt",
            displayName: "NanoGPT",
            legacyEnvKeys: ["NANO_GPT_API_KEY"],
            apiBaseURL: "https://nano-gpt.com/api/v1"
        ),
        ProviderCatalogEntry(
            id: "nebius",
            displayName: "Nebius Token Factory",
            legacyEnvKeys: ["NEBIUS_API_KEY"],
            apiBaseURL: "https://api.tokenfactory.nebius.com/v1"
        ),
        ProviderCatalogEntry(
            id: "nova",
            displayName: "Nova",
            legacyEnvKeys: ["NOVA_API_KEY"],
            apiBaseURL: "https://api.nova.amazon.com/v1"
        ),
        ProviderCatalogEntry(
            id: "novita-ai",
            displayName: "NovitaAI",
            legacyEnvKeys: ["NOVITA_API_KEY"],
            apiBaseURL: "https://api.novita.ai/openai"
        ),
        ProviderCatalogEntry(
            id: "nvidia",
            displayName: "Nvidia",
            legacyEnvKeys: ["NVIDIA_API_KEY"],
            apiBaseURL: "https://integrate.api.nvidia.com/v1"
        ),
        ProviderCatalogEntry(
            id: "ollama-cloud",
            displayName: "Ollama Cloud",
            legacyEnvKeys: ["OLLAMA_API_KEY"],
            apiBaseURL: "https://ollama.com/v1"
        ),
        ProviderCatalogEntry(
            id: "openai",
            displayName: "OpenAI",
            legacyEnvKeys: ["OPENAI_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "opencode",
            displayName: "OpenCode Zen",
            legacyEnvKeys: ["OPENCODE_API_KEY"],
            apiBaseURL: "https://opencode.ai/zen/v1"
        ),
        ProviderCatalogEntry(
            id: "opencode-go",
            displayName: "OpenCode Go",
            legacyEnvKeys: ["OPENCODE_API_KEY"],
            apiBaseURL: "https://opencode.ai/zen/go/v1"
        ),
        ProviderCatalogEntry(
            id: "openrouter",
            displayName: "OpenRouter",
            legacyEnvKeys: ["OPENROUTER_API_KEY"],
            apiBaseURL: "https://openrouter.ai/api/v1"
        ),
        ProviderCatalogEntry(
            id: "ovhcloud",
            displayName: "OVHcloud AI Endpoints",
            legacyEnvKeys: ["OVHCLOUD_API_KEY"],
            apiBaseURL: "https://oai.endpoints.kepler.ai.cloud.ovh.net/v1"
        ),
        ProviderCatalogEntry(
            id: "perplexity",
            displayName: "Perplexity",
            legacyEnvKeys: ["PERPLEXITY_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "poe",
            displayName: "Poe",
            legacyEnvKeys: ["POE_API_KEY"],
            apiBaseURL: "https://api.poe.com/v1"
        ),
        ProviderCatalogEntry(
            id: "privatemode-ai",
            displayName: "Privatemode AI",
            legacyEnvKeys: ["PRIVATEMODE_API_KEY", "PRIVATEMODE_ENDPOINT"],
            apiBaseURL: "http://localhost:8080/v1"
        ),
        ProviderCatalogEntry(
            id: "qihang-ai",
            displayName: "QiHang",
            legacyEnvKeys: ["QIHANG_API_KEY"],
            apiBaseURL: "https://api.qhaigc.net/v1"
        ),
        ProviderCatalogEntry(
            id: "qiniu-ai",
            displayName: "Qiniu",
            legacyEnvKeys: ["Qiniu_API_KEY"],
            apiBaseURL: "https://api.qnaigc.com.com/v1"
        ),
        ProviderCatalogEntry(
            id: "requesty",
            displayName: "Requesty",
            legacyEnvKeys: ["REQUESTY_API_KEY"],
            apiBaseURL: "https://router.requesty.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "sap-ai-core",
            displayName: "SAP AI Core",
            legacyEnvKeys: ["AICORE_SERVICE_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "scaleway",
            displayName: "Scaleway",
            legacyEnvKeys: ["SCALEWAY_API_KEY"],
            apiBaseURL: "https://api.scaleway.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "siliconflow",
            displayName: "SiliconFlow",
            legacyEnvKeys: ["SILICONFLOW_API_KEY"],
            apiBaseURL: "https://api.siliconflow.com/v1"
        ),
        ProviderCatalogEntry(
            id: "siliconflow-cn",
            displayName: "SiliconFlow (China)",
            legacyEnvKeys: ["SILICONFLOW_CN_API_KEY"],
            apiBaseURL: "https://api.siliconflow.cn/v1"
        ),
        ProviderCatalogEntry(
            id: "stackit",
            displayName: "STACKIT",
            legacyEnvKeys: ["STACKIT_API_KEY"],
            apiBaseURL: "https://api.openai-compat.model-serving.eu01.onstackit.cloud/v1"
        ),
        ProviderCatalogEntry(
            id: "stepfun",
            displayName: "StepFun",
            legacyEnvKeys: ["STEPFUN_API_KEY"],
            apiBaseURL: "https://api.stepfun.com/v1"
        ),
        ProviderCatalogEntry(
            id: "submodel",
            displayName: "submodel",
            legacyEnvKeys: ["SUBMODEL_INSTAGEN_ACCESS_KEY"],
            apiBaseURL: "https://llm.submodel.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "synthetic",
            displayName: "Synthetic",
            legacyEnvKeys: ["SYNTHETIC_API_KEY"],
            apiBaseURL: "https://api.synthetic.new/v1"
        ),
        ProviderCatalogEntry(
            id: "togetherai",
            displayName: "Together AI",
            legacyEnvKeys: ["TOGETHER_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "upstage",
            displayName: "Upstage",
            legacyEnvKeys: ["UPSTAGE_API_KEY"],
            apiBaseURL: "https://api.upstage.ai/v1/solar"
        ),
        ProviderCatalogEntry(
            id: "v0",
            displayName: "v0",
            legacyEnvKeys: ["V0_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "venice",
            displayName: "Venice AI",
            legacyEnvKeys: ["VENICE_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "vercel",
            displayName: "Vercel AI Gateway",
            legacyEnvKeys: ["AI_GATEWAY_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "vivgrid",
            displayName: "Vivgrid",
            legacyEnvKeys: ["VIVGRID_API_KEY"],
            apiBaseURL: "https://api.vivgrid.com/v1"
        ),
        ProviderCatalogEntry(
            id: "vultr",
            displayName: "Vultr",
            legacyEnvKeys: ["VULTR_API_KEY"],
            apiBaseURL: "https://api.vultrinference.com/v1"
        ),
        ProviderCatalogEntry(
            id: "wandb",
            displayName: "Weights & Biases",
            legacyEnvKeys: ["WANDB_API_KEY"],
            apiBaseURL: "https://api.inference.wandb.ai/v1"
        ),
        ProviderCatalogEntry(
            id: "xai",
            displayName: "xAI",
            legacyEnvKeys: ["XAI_API_KEY"],
            apiBaseURL: nil
        ),
        ProviderCatalogEntry(
            id: "xiaomi",
            displayName: "Xiaomi",
            legacyEnvKeys: ["XIAOMI_API_KEY"],
            apiBaseURL: "https://api.xiaomimimo.com/v1"
        ),
        ProviderCatalogEntry(
            id: "zai",
            displayName: "Z.AI",
            legacyEnvKeys: ["ZHIPU_API_KEY"],
            apiBaseURL: "https://api.z.ai/api/paas/v4"
        ),
        ProviderCatalogEntry(
            id: "zai-coding-plan",
            displayName: "Z.AI Coding Plan",
            legacyEnvKeys: ["ZHIPU_API_KEY"],
            apiBaseURL: "https://api.z.ai/api/coding/paas/v4"
        ),
        ProviderCatalogEntry(
            id: "zenmux",
            displayName: "ZenMux",
            legacyEnvKeys: ["ZENMUX_API_KEY"],
            apiBaseURL: "https://zenmux.ai/api/anthropic/v1"
        ),
        ProviderCatalogEntry(
            id: "zhipuai",
            displayName: "Zhipu AI",
            legacyEnvKeys: ["ZHIPU_API_KEY"],
            apiBaseURL: "https://open.bigmodel.cn/api/paas/v4"
        ),
        ProviderCatalogEntry(
            id: "zhipuai-coding-plan",
            displayName: "Zhipu AI Coding Plan",
            legacyEnvKeys: ["ZHIPU_API_KEY"],
            apiBaseURL: "https://open.bigmodel.cn/api/coding/paas/v4"
        ),
        ProviderCatalogEntry(
            id: "gemini",
            displayName: "Gemini",
            legacyEnvKeys: ["GEMINI_API_KEY", "GOOGLE_GENERATIVE_AI_API_KEY"],
            apiBaseURL: "https://generativelanguage.googleapis.com/v1beta"
        ),
        ProviderCatalogEntry(
            id: "together",
            displayName: "Together",
            legacyEnvKeys: ["TOGETHER_API_KEY"],
            apiBaseURL: "https://api.together.xyz/v1"
        ),
    ]

    public static let entryByID: [String: ProviderCatalogEntry] = {
        Dictionary(uniqueKeysWithValues: allEntries.map { ($0.id, $0) })
    }()

    public static let allProviders: [AIProvider] = {
        allEntries.compactMap { AIProvider(rawValue: $0.id) }
    }()

    public static func entry(for provider: AIProvider) -> ProviderCatalogEntry? {
        entryByID[provider.rawValue]
    }
}

