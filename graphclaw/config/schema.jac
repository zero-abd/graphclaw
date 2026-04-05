# graphclaw/config/schema.jac
# Configuration schema -- mirrors nanobot's Pydantic approach but in Jac obj types

import from pydantic { BaseModel, Field }
import from pydantic_settings { BaseSettings }
import from typing { Optional, Dict, Any, List }

# -- LLM Provider --------------------------------------------------------------

obj ProviderConfig {
    has api_key: str = "";
    has base_url: str = "";
    has model: str = "";
    has extra: dict = {};
}

obj ProvidersConfig {
    has default_provider: str = "openrouter";
    has openrouter: ProviderConfig = ProviderConfig(
        base_url="https://openrouter.ai/api/v1",
        model="anthropic/claude-sonnet-4-6"
    );
    has anthropic: ProviderConfig = ProviderConfig(model="claude-sonnet-4-6");
    has openai: ProviderConfig = ProviderConfig(model="gpt-4o");
    has ollama: ProviderConfig = ProviderConfig(
        base_url="http://localhost:11434",
        model="llama3"
    );
    has custom: ProviderConfig = ProviderConfig();
}

# -- Agent Defaults -------------------------------------------------------------

obj DreamConfig {
    has enabled: bool = True;
    has interval_hours: int = 2;
    has max_batch_size: int = 20;
    has max_iterations: int = 10;
}

obj AgentDefaults {
    has model: str = "openrouter/anthropic/claude-sonnet-4-6";
    has max_tokens: int = 8192;
    has context_window_tokens: int = 65536;
    has temperature: float = 0.7;
    has max_tool_iterations: int = 200;
    has max_tool_result_chars: int = 16000;
    has reasoning_effort: str = "";   # "" | "low" | "medium" | "high"
    has timezone: str = "UTC";
    has dream: DreamConfig = DreamConfig();
}

# -- Tools ---------------------------------------------------------------------

obj ExecToolConfig {
    has enabled: bool = True;
    has timeout: int = 300;
    has restrict_to_workspace: bool = True;
}

obj WebSearchConfig {
    has enabled: bool = True;
    has max_results: int = 10;
}

obj WebToolsConfig {
    has enabled: bool = True;
    has search: WebSearchConfig = WebSearchConfig();
    has proxy: str = "";
}

obj ToolsConfig {
    has exec: ExecToolConfig = ExecToolConfig();
    has web: WebToolsConfig = WebToolsConfig();
    has mcp_servers: dict = {};
}

# -- Channels ------------------------------------------------------------------

obj TelegramConfig {
    has enabled: bool = False;
    has bot_token: str = "";
    has allowed_user_ids: list = [];
    has streaming: bool = True;
}

obj DiscordConfig {
    has enabled: bool = False;
    has bot_token: str = "";
    has guild_ids: list = [];
    has streaming: bool = True;
}

obj SlackConfig {
    has enabled: bool = False;
    has bot_token: str = "";
    has app_token: str = "";
    has signing_secret: str = "";
    has streaming: bool = True;
}

obj EmailConfig {
    has enabled: bool = False;
    has smtp_host: str = "";
    has smtp_port: int = 587;
    has imap_host: str = "";
    has imap_port: int = 993;
    has username: str = "";
    has password: str = "";
    has poll_interval_s: int = 60;
}

obj WhatsAppConfig {
    has enabled: bool = False;
    has bridge_url: str = "http://localhost:3000";
    has auth_token: str = "";
}

obj ChannelsConfig {
    has send_progress: bool = True;
    has send_tool_hints: bool = False;
    has send_max_retries: int = 3;
    has telegram: TelegramConfig = TelegramConfig();
    has discord: DiscordConfig = DiscordConfig();
    has slack: SlackConfig = SlackConfig();
    has email: EmailConfig = EmailConfig();
    has whatsapp: WhatsAppConfig = WhatsAppConfig();
}

# -- Skills --------------------------------------------------------------------

obj SkillsConfig {
    has registry_url: str = "https://clawhub.ai/api/v1";   # ClawHub public registry
    has auto_update: bool = False;
    has installed_path: str = "~/.graphclaw/skills/installed";
}

# -- Auth (multi-user) ---------------------------------------------------------

obj AuthConfig {
    has enabled: bool = False;    # flipped to True in multi-user install
    has secret_key: str = "";
    has token_expiry_hours: int = 168;  # 7 days
}

# -- Root Config ---------------------------------------------------------------

obj Config {
    has workspace: str = "~/.graphclaw/workspace";
    has multi_user: bool = False;
    has agents: AgentDefaults = AgentDefaults();
    has providers: ProvidersConfig = ProvidersConfig();
    has tools: ToolsConfig = ToolsConfig();
    has channels: ChannelsConfig = ChannelsConfig();
    has skills: SkillsConfig = SkillsConfig();
    has auth: AuthConfig = AuthConfig();
    has log_level: str = "INFO";
}
