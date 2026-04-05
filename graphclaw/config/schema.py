"""Configuration schema for Graphclaw."""
from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Optional, Dict, Any, List


class ProviderConfig(BaseModel):
    api_key: str = ""
    base_url: str = ""


class DreamConfig(BaseModel):
    enabled: bool = True
    interval_hours: int = 2


class AgentDefaults(BaseModel):
    model: str = "openrouter/anthropic/claude-sonnet-4-6"
    max_tokens: int = 8192
    temperature: float = 0.7
    max_tool_iterations: int = 200
    dream: DreamConfig = Field(default_factory=DreamConfig)


class ChannelConfig(BaseModel):
    enabled: bool = False
    bot_token: str = ""
    app_token: str = ""  # slack only
    allowed_ids: List[str] = Field(default_factory=list)


class AuthConfig(BaseModel):
    enabled: bool = False
    secret_key: str = ""


class SkillsConfig(BaseModel):
    registry_url: str = "https://clawhub.ai/api/v1"
    installed_path: str = ""


class Config(BaseModel):
    workspace: str = ""
    multi_user: bool = False
    agents: AgentDefaults = Field(default_factory=AgentDefaults)
    providers: Dict[str, Any] = Field(default_factory=lambda: {
        "default_provider": "openrouter",
        "openrouter": {"api_key": "", "base_url": "https://openrouter.ai/api/v1"},
        "anthropic": {"api_key": ""},
        "openai": {"api_key": ""},
    })
    channels: Dict[str, Any] = Field(default_factory=lambda: {
        "telegram": {"enabled": False, "bot_token": ""},
        "discord": {"enabled": False, "bot_token": ""},
        "slack": {"enabled": False, "bot_token": "", "app_token": ""},
        "email": {"enabled": False},
        "whatsapp": {"enabled": False},
    })
    auth: AuthConfig = Field(default_factory=AuthConfig)
    skills: SkillsConfig = Field(default_factory=SkillsConfig)
