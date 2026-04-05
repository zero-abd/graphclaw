"""High-level Loveable and Base44 tools for easy website/app generation."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from graphclaw.channels.bus import OutboundMessage, bus
from graphclaw.skills.registry.base44 import skill as base44_skill
from graphclaw.skills.registry.loveable import skill as loveable_skill


class _ProgressMixin:
    def __init__(self, *, channel: str, chat_id: str):
        self._channel = channel
        self._chat_id = chat_id

    def _notify(self, text: str) -> None:
        if self._channel and self._chat_id and self._channel != "cli":
            bus.publish_outbound(OutboundMessage(channel=self._channel, chat_id=self._chat_id, text=text))


class LoveableLandingPageTool(_ProgressMixin):
    name = "loveable_landing_page"
    description = (
        "Generate an official Lovable Build with URL link for a polished landing page. "
        "Great for quickly creating a hosted-looking website concept the user can open in Lovable and publish."
    )
    parameters = {
        "type": "object",
        "properties": {
            "brief": {"type": "string", "description": "What the landing page is for"},
            "brand_name": {"type": "string", "description": "Optional brand/product name", "default": ""},
            "primary_cta": {"type": "string", "description": "Optional primary CTA text", "default": ""},
            "style_notes": {"type": "string", "description": "Optional style/visual direction", "default": ""},
            "images": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Optional public image URLs to include in the Lovable build link",
                "default": [],
            },
            "open_browser": {"type": "boolean", "description": "Open the generated link locally", "default": False},
        },
        "required": ["brief"],
    }

    async def execute(self, **kwargs: Any) -> str:
        self._notify("Generating your Lovable build link…")
        result = loveable_skill.build_landing_page_url(
            brief=str(kwargs.get("brief", "")),
            brand_name=str(kwargs.get("brand_name", "")),
            primary_cta=str(kwargs.get("primary_cta", "")),
            style_notes=str(kwargs.get("style_notes", "")),
            images=kwargs.get("images", []) or [],
            open_browser=bool(kwargs.get("open_browser", False)),
        )
        self._notify(f"Lovable build link ready: {result['url']}")
        return json.dumps(result, indent=2)


class LoveableBuildUrlTool(_ProgressMixin):
    name = "loveable_build_url"
    description = "Generate a raw official Lovable Build with URL link from any prompt."
    parameters = {
        "type": "object",
        "properties": {
            "prompt": {"type": "string", "description": "Full Lovable build prompt"},
            "images": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Optional public image URLs to attach",
                "default": [],
            },
            "open_browser": {"type": "boolean", "description": "Open the generated link locally", "default": False},
        },
        "required": ["prompt"],
    }

    async def execute(self, **kwargs: Any) -> str:
        self._notify("Generating a Lovable build URL…")
        result = loveable_skill.build_with_url(
            prompt=str(kwargs.get("prompt", "")),
            images=kwargs.get("images", []) or [],
            open_browser=bool(kwargs.get("open_browser", False)),
        )
        self._notify(f"Lovable build link ready: {result['url']}")
        return json.dumps(result, indent=2)


class Base44CreateProjectTool(_ProgressMixin):
    name = "base44_create_project"
    description = (
        "Create a Base44 project with the official Base44 CLI flow. "
        "Use this for managed app scaffolding and optional deploys."
    )
    parameters = {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "Project name"},
            "path": {"type": "string", "description": "Optional target directory", "default": ""},
            "template": {"type": "string", "description": "Base44 CLI template name", "default": "basic"},
            "deploy": {"type": "boolean", "description": "Deploy immediately if supported", "default": True},
        },
        "required": ["name"],
    }

    async def execute(self, **kwargs: Any) -> str:
        name = str(kwargs.get("name", "")).strip()
        self._notify(f"Scaffolding Base44 project `{name}`…")
        result = base44_skill.create_project(
            name=name,
            path=str(kwargs.get("path", "")),
            template=str(kwargs.get("template", "basic")),
            deploy=bool(kwargs.get("deploy", True)),
        )
        if result.get("ok"):
            urls = result.get("urls", [])
            if urls:
                self._notify(f"Base44 project ready. URLs found: {' '.join(urls[:2])}")
            else:
                self._notify("Base44 project scaffolded successfully.")
        return json.dumps(result, indent=2)


class Base44DeployProjectTool(_ProgressMixin):
    name = "base44_deploy_project"
    description = "Deploy an existing Base44 project with the official CLI."
    parameters = {
        "type": "object",
        "properties": {
            "project_path": {"type": "string", "description": "Path to the Base44 project"},
        },
        "required": ["project_path"],
    }

    async def execute(self, **kwargs: Any) -> str:
        project_path = str(kwargs.get("project_path", "")).strip()
        self._notify(f"Deploying Base44 project from {project_path}…")
        result = base44_skill.deploy_project(project_path)
        if result.get("ok") and result.get("urls"):
            self._notify(f"Base44 deploy complete. URL: {result['urls'][0]}")
        return json.dumps(result, indent=2)


def builder_platform_tools(*, channel: str, chat_id: str) -> list[Any]:
    return [
        LoveableLandingPageTool(channel=channel, chat_id=chat_id),
        LoveableBuildUrlTool(channel=channel, chat_id=chat_id),
        Base44CreateProjectTool(channel=channel, chat_id=chat_id),
        Base44DeployProjectTool(channel=channel, chat_id=chat_id),
    ]
