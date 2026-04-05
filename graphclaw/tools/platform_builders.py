"""High-level Loveable and Base44 tools for easy website/app generation."""
from __future__ import annotations

import asyncio
import json
from typing import Any

from graphclaw.browser.automation import capture_url_screenshot, login_loveable_and_capture_progress
from graphclaw.channels.bus import OutboundMessage, bus
from graphclaw.credentials.platform_auth import (
    clear_service_credentials,
    get_service_credentials,
    save_service_credentials,
)
from graphclaw.skills.registry.base44 import skill as base44_skill
from graphclaw.skills.registry.loveable import skill as loveable_skill


class _ProgressMixin:
    def __init__(self, *, channel: str, chat_id: str):
        self._channel = channel
        self._chat_id = chat_id

    def _notify(self, text: str) -> None:
        if self._channel and self._chat_id and self._channel != "cli":
            bus.publish_outbound(OutboundMessage(channel=self._channel, chat_id=self._chat_id, text=text))

    async def _notify_async(self, text: str) -> None:
        self._notify(text)

    def _send_media(self, text: str, media: list[str]) -> None:
        if self._channel and self._chat_id and self._channel != "cli":
            bus.publish_outbound(OutboundMessage(channel=self._channel, chat_id=self._chat_id, text=text, media=media))


class SaveLoveableCredentialsTool(_ProgressMixin):
    name = "save_loveable_credentials"
    description = "Securely store the user's Loveable login email/username and password for browser-assisted Lovable tasks."
    parameters = {
        "type": "object",
        "properties": {
            "username": {"type": "string", "description": "Loveable login email/username"},
            "password": {"type": "string", "description": "Loveable login password"},
        },
        "required": ["username", "password"],
    }

    async def execute(self, **kwargs: Any) -> str:
        save_service_credentials(
            "loveable",
            channel=self._channel,
            chat_id=self._chat_id,
            user_id=getattr(self, "_user_id", "user"),
            username=str(kwargs.get("username", "")),
            password=str(kwargs.get("password", "")),
        )
        return "Saved your Loveable login securely for this chat user. I can now use it for browser-assisted Lovable flows."


class ClearLoveableCredentialsTool(_ProgressMixin):
    name = "clear_loveable_credentials"
    description = "Delete the saved Loveable login for this chat user."
    parameters = {"type": "object", "properties": {}}

    async def execute(self, **kwargs: Any) -> str:
        removed = clear_service_credentials(
            "loveable",
            channel=self._channel,
            chat_id=self._chat_id,
            user_id=getattr(self, "_user_id", "user"),
        )
        return "Removed your saved Loveable login." if removed else "No saved Loveable login was found for this chat user."


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
            "send_progress_updates": {
                "type": "boolean",
                "description": "If true and Lovable credentials are saved, log into Lovable in a browser and send progress screenshots to the active chat.",
                "default": False,
            },
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
        if bool(kwargs.get("send_progress_updates", False)):
            credentials = get_service_credentials(
                "loveable",
                channel=self._channel,
                chat_id=self._chat_id,
                user_id=getattr(self, "_user_id", "user"),
            )
            if credentials is None:
                self._notify("No saved Loveable login found for screenshot progress. Ask me to save your Loveable username and password first.")
            else:
                try:
                    screenshots = await login_loveable_and_capture_progress(
                        result["url"],
                        username=credentials["username"],
                        password=credentials["password"],
                        notify=self._notify_async,
                    )
                    self._send_media("Lovable progress screenshots", screenshots)
                    result["progress_screenshots"] = screenshots
                except Exception as exc:
                    self._notify(f"Lovable screenshot progress failed: {exc}")
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
            "send_progress_updates": {
                "type": "boolean",
                "description": "If true and Lovable credentials are saved, log into Lovable in a browser and send progress screenshots to the active chat.",
                "default": False,
            },
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
        if bool(kwargs.get("send_progress_updates", False)):
            credentials = get_service_credentials(
                "loveable",
                channel=self._channel,
                chat_id=self._chat_id,
                user_id=getattr(self, "_user_id", "user"),
            )
            if credentials is None:
                self._notify("No saved Loveable login found for screenshot progress. Ask me to save your Loveable username and password first.")
            else:
                try:
                    screenshots = await login_loveable_and_capture_progress(
                        result["url"],
                        username=credentials["username"],
                        password=credentials["password"],
                        notify=self._notify_async,
                    )
                    self._send_media("Lovable progress screenshots", screenshots)
                    result["progress_screenshots"] = screenshots
                except Exception as exc:
                    self._notify(f"Lovable screenshot progress failed: {exc}")
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
            "send_progress_updates": {
                "type": "boolean",
                "description": "If true and deploy returns a URL, capture a browser screenshot and send it to the active chat.",
                "default": False,
            },
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
                if bool(kwargs.get("send_progress_updates", False)):
                    try:
                        screenshot = await capture_url_screenshot(urls[0], label="base44-preview")
                        self._send_media("Base44 preview screenshot", [screenshot])
                        result["preview_screenshot"] = screenshot
                    except Exception as exc:
                        self._notify(f"Base44 screenshot capture failed: {exc}")
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
            "send_progress_updates": {
                "type": "boolean",
                "description": "If true and deploy returns a URL, capture a browser screenshot and send it to the active chat.",
                "default": False,
            },
        },
        "required": ["project_path"],
    }

    async def execute(self, **kwargs: Any) -> str:
        project_path = str(kwargs.get("project_path", "")).strip()
        self._notify(f"Deploying Base44 project from {project_path}…")
        result = base44_skill.deploy_project(project_path)
        if result.get("ok") and result.get("urls"):
            self._notify(f"Base44 deploy complete. URL: {result['urls'][0]}")
            if bool(kwargs.get("send_progress_updates", False)):
                try:
                    screenshot = await capture_url_screenshot(result["urls"][0], label="base44-live")
                    self._send_media("Base44 deployment screenshot", [screenshot])
                    result["deployment_screenshot"] = screenshot
                except Exception as exc:
                    self._notify(f"Base44 screenshot capture failed: {exc}")
        return json.dumps(result, indent=2)


def builder_platform_tools(*, channel: str, chat_id: str, user_id: str = "user") -> list[Any]:
    save_tool = SaveLoveableCredentialsTool(channel=channel, chat_id=chat_id)
    save_tool._user_id = user_id
    clear_tool = ClearLoveableCredentialsTool(channel=channel, chat_id=chat_id)
    clear_tool._user_id = user_id
    return [
        save_tool,
        clear_tool,
        LoveableLandingPageTool(channel=channel, chat_id=chat_id),
        LoveableBuildUrlTool(channel=channel, chat_id=chat_id),
        Base44CreateProjectTool(channel=channel, chat_id=chat_id),
        Base44DeployProjectTool(channel=channel, chat_id=chat_id),
    ]
