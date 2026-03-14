module modules.services.ai_providers;

import std.stdio;
import std.net.curl;
import std.json;
import std.conv;
import std.file : exists, readText, write;
import std.path : buildPath;
import std.process : environment;

/// Struct to hold provider connection data
struct AIProviderProfile
{
    string id;            // e.g., "openai", "anthropic", "gemini"
    string name;          // e.g., "OpenAI"
    string websiteUrl;    // URL to generate keys
    string defaultEndpoint; 
    string apiVersion;    // optional
}

/// A registry mapping of known AI Providers
static const AIProviderProfile[] KNOWN_PROVIDERS = [
    AIProviderProfile("openai", "OpenAI", "https://platform.openai.com/api-keys", "https://api.openai.com/v1/chat/completions", ""),
    AIProviderProfile("anthropic", "Anthropic", "https://console.anthropic.com/settings/keys", "https://api.anthropic.com/v1/messages", "2023-06-01"),
    AIProviderProfile("gemini", "Google Gemini", "https://aistudio.google.com/app/apikey", "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent", ""),
    AIProviderProfile("mistral", "Mistral AI", "https://console.mistral.ai/api-keys/", "https://api.mistral.ai/v1/chat/completions", ""),
    AIProviderProfile("groq", "Groq", "https://console.groq.com/keys", "https://api.groq.com/openai/v1/chat/completions", ""),
    AIProviderProfile("openrouter", "OpenRouter", "https://openrouter.ai/keys", "https://openrouter.ai/api/v1/chat/completions", ""),
    AIProviderProfile("moonshot", "Moonshot / Kimi", "https://platform.moonshot.cn/console/api-keys", "https://api.moonshot.cn/v1/chat/completions", ""),
    AIProviderProfile("deepseek", "DeepSeek", "https://platform.deepseek.com/api_keys", "https://api.deepseek.com/chat/completions", ""),
    AIProviderProfile("zhipu", "Zhipu AI (GLM)", "https://open.bigmodel.cn/usercenter/apikeys", "https://open.bigmodel.cn/api/paas/v4/chat/completions", ""),
    AIProviderProfile("dashscope", "Alibaba DashScope (Qwen)", "https://dashscope.console.aliyun.com/apiKey", "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", ""),
    AIProviderProfile("qianfan", "Baidu Qianfan", "https://console.bce.baidu.com/qianfan/ais/console/applicationConsole/application", "https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop/chat/completions", ""),
    AIProviderProfile("hunyuan", "Tencent Hunyuan", "https://console.cloud.tencent.com/hunyuan", "https://api.hunyuan.cloud.tencent.com/v1/chat/completions", "")
];

/// Get a config path for a specific provider
string getProviderKeyPath(string configRoot, string providerId)
{
    return buildPath(configRoot, "ai_keys", providerId ~ ".txt");
}

/// Retrieve the locally saved key for the provider.
string getProviderKey(string configRoot, string providerId)
{
    string path = getProviderKeyPath(configRoot, providerId);
    if (exists(path)) return readText(path);
    return "";
}

/// Save a new key for the provider.
void saveProviderKey(string configRoot, string providerId, string keyData)
{
    import std.file : mkdirRecurse;
    string dir = buildPath(configRoot, "ai_keys");
    if (!exists(dir)) mkdirRecurse(dir);
    write(getProviderKeyPath(configRoot, providerId), keyData);
}

/// Interface for making generic completions calls
interface IAIService
{
    string generateText(string systemPrompt, string userPrompt);
}

// Pseudo-implementation to demonstrate API integration points.
// Actually making calls via std.net.curl here.
class ProviderClient : IAIService
{
    private string apiKey;
    private AIProviderProfile profile;
    
    this(AIProviderProfile profile, string apiKey)
    {
        this.profile = profile;
        this.apiKey = apiKey;
    }
    
    string generateText(string systemPrompt, string userPrompt)
    {
        if (apiKey.length == 0) return "Error: API Key not set for " ~ profile.name;
        
        // This is a stub implementation meant to handle formatting for the various APIs
        // Typically we'd use vibe.d HTTP or std.net.curl properly formatted.
        // For DevCentr, this demonstrates where the request execution occurs.
        return "[Mocked AI Response from " ~ profile.name ~ "]\n\nGenerated content for:\n" ~ userPrompt[0 .. (userPrompt.length > 50 ? 50 : $)] ~ "...";
    }
}
