"""High-level Loveable and Base44 tools for easy website/app generation."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path
from typing import Any

from graphclaw.channels.bus import OutboundMessage, bus
from graphclaw.credentials.platform_auth import (
    clear_service_credentials,
    get_service_credentials,
    save_service_credentials,
)
from graphclaw.mcp.platforms import (
    base44_create_app,
    ensure_recommended_platform_servers,
    mcp_result_text,
    playwright_call,
    playwright_output_dir,
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

    def _playwright_screenshot_file(self, label: str) -> tuple[str, str | None]:
        out_dir = playwright_output_dir("playwright")
        filename = f"{label}-{next(tempfile._get_candidate_names())}.png"
        if out_dir is None:
            return filename, None
        out_dir.mkdir(parents=True, exist_ok=True)
        return filename, str(out_dir / filename)

    async def _maybe_send_playwright_screenshot(self, label: str, caption: str) -> str | None:
        filename, absolute_path = self._playwright_screenshot_file(label)
        await playwright_call(
            "browser_take_screenshot",
            {"type": "png", "filename": filename, "fullPage": True},
        )
        if absolute_path and Path(absolute_path).exists():
            self._send_media(caption, [absolute_path])
            return absolute_path
        return None

    async def _run_loveable_publish_via_mcp(
        self,
        *,
        build_url: str,
        username: str,
        password: str,
        publish_slug: str = "",
        workspace_name: str = "",
        send_progress_updates: bool = False,
    ) -> dict[str, Any]:
        await self._notify_async("Driving Lovable through Playwright MCP…")
        await playwright_call("browser_navigate", {"url": build_url})
        await playwright_call("browser_wait_for", {"time": 3})

        login_script = f"""
        async (page) => {{
          const username = {json.dumps(username)};
          const password = {json.dumps(password)};
          const workspaceName = {json.dumps(workspace_name)};
          const fillFirst = async (selectors, value) => {{
            for (const selector of selectors) {{
              const loc = page.locator(selector);
              if (await loc.count()) {{
                const el = loc.first();
                if (await el.isVisible()) {{
                  await el.fill(value);
                  return true;
                }}
              }}
            }}
            return false;
          }};
          const clickFirst = async (selectors) => {{
            for (const selector of selectors) {{
              const loc = page.locator(selector);
              if (await loc.count()) {{
                const el = loc.first();
                if (await el.isVisible()) {{
                  await el.click();
                  return true;
                }}
              }}
            }}
            return false;
          }};
          await fillFirst(['input[type=\"email\"]','input[name*=email i]','input[autocomplete=\"email\"]'], username);
          await clickFirst(['button:has-text(\"Continue\")','button:has-text(\"Next\")','button:has-text(\"Log in\")','button:has-text(\"Sign in\")','button[type=\"submit\"]']);
          await page.waitForTimeout(1200);
          await fillFirst(['input[type=\"password\"]','input[name*=password i]','input[autocomplete=\"current-password\"]'], password);
          await clickFirst(['button:has-text(\"Log in\")','button:has-text(\"Sign in\")','button:has-text(\"Continue\")','button[type=\"submit\"]']);
          await page.waitForTimeout(5000);
          if (workspaceName) {{
            const button = page.getByRole('button', {{ name: new RegExp(workspaceName, 'i') }});
            if (await button.count()) await button.first().click();
          }} else {{
            const workspaceButtons = page.locator('button');
            const count = await workspaceButtons.count();
            for (let i = 0; i < Math.min(count, 12); i++) {{
              const btn = workspaceButtons.nth(i);
              const text = ((await btn.innerText().catch(() => '')) || '').trim();
              if (text && !/log in|sign in|continue|next/i.test(text)) {{
                await btn.click().catch(() => null);
                break;
              }}
            }}
          }}
          await page.waitForTimeout(5000);
          return {{ url: page.url(), title: await page.title() }};
        }}
        """
        login_result = await playwright_call("browser_run_code", {"code": login_script})
        if send_progress_updates:
            await self._maybe_send_playwright_screenshot("loveable-login", "Lovable login/build progress")

        publish_script = f"""
        async (page) => {{
          const publishSlug = {json.dumps(publish_slug)};
          const waitForPublish = async () => {{
            for (let i = 0; i < 60; i++) {{
              const candidate = page.getByRole('button', {{ name: /publish|update/i }});
              if (await candidate.count()) return true;
              await page.waitForTimeout(3000);
            }}
            return false;
          }};
          const ready = await waitForPublish();
          if (!ready) return {{ publishedUrl: '', ready: false, url: page.url() }};
          const publishButton = page.getByRole('button', {{ name: /publish|update/i }}).first();
          await publishButton.click();
          await page.waitForTimeout(1500);
          if (publishSlug) {{
            const inputs = page.locator('input');
            const count = await inputs.count();
            for (let i = 0; i < count; i++) {{
              const input = inputs.nth(i);
              const value = await input.inputValue().catch(() => '');
              const placeholder = await input.getAttribute('placeholder').catch(() => '');
              if (/lovable\\.app/i.test(value || '') || /lovable/i.test(placeholder || '')) {{
                await input.fill(publishSlug);
                break;
              }}
            }}
          }}
          const anyone = page.getByRole('button', {{ name: /anyone/i }});
          if (await anyone.count()) await anyone.first().click().catch(() => null);
          const finalButton = page.getByRole('button', {{ name: /^publish$|publish to/i }});
          if (await finalButton.count()) await finalButton.first().click();
          await page.waitForTimeout(5000);
          let publishedUrl = '';
          const links = await page.locator('a[href*=\"lovable.app\"]').evaluateAll(nodes => nodes.map(n => n.href));
          if (links.length) publishedUrl = links[0];
          if (!publishedUrl) {{
            const inputs = await page.locator('input').evaluateAll(nodes => nodes.map(n => n.value || '').filter(v => v.includes('lovable.app')));
            if (inputs.length) publishedUrl = inputs[0];
          }}
          return {{ publishedUrl, ready: true, url: page.url() }};
        }}
        """
        publish_result = await playwright_call("browser_run_code", {"code": publish_script})
        if send_progress_updates:
            await self._maybe_send_playwright_screenshot("loveable-published", "Lovable published result")

        published_url = ""
        structured = publish_result.get("structuredContent") if isinstance(publish_result, dict) else None
        if isinstance(structured, dict):
            published_url = str(
                structured.get("publishedUrl")
                or structured.get("published_url")
                or structured.get("url")
                or ""
            ).strip()
        if not published_url:
            text = mcp_result_text(publish_result)
            try:
                parsed = json.loads(text)
                if isinstance(parsed, dict):
                    published_url = str(
                        parsed.get("publishedUrl")
                        or parsed.get("published_url")
                        or parsed.get("url")
                        or ""
                    ).strip()
            except Exception:
                pass
        if not published_url:
            text = mcp_result_text(publish_result)
            for token in text.replace("\n", " ").split():
                if "lovable.app" in token:
                    published_url = token.strip(" ,)")
                    break

        return {
            "build_url": build_url,
            "login_result": login_result,
            "publish_result": publish_result,
            "published_url": published_url,
        }


class ConfigurePlatformMCPServersTool(_ProgressMixin):
    name = "configure_platform_mcp_servers"
    description = "Add the recommended Playwright, Base44, and Base44 docs MCP server configs to Graphclaw."
    parameters = {"type": "object", "properties": {}}

    async def execute(self, **kwargs: Any) -> str:
        result = ensure_recommended_platform_servers()
        return json.dumps(
            {
                "message": "Recommended MCP servers saved to config.",
                "added": result.get("added", []),
                "servers": list(result.get("servers", {}).keys()),
            },
            indent=2,
        )


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
        "Create a Lovable landing page flow. If Playwright MCP and Lovable credentials are configured, "
        "Graphclaw will try to drive Lovable in the browser, publish the site, and return the shareable URL."
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
                "description": "If true, send Lovable progress screenshots back to the active chat when Playwright MCP is configured.",
                "default": True,
            },
            "auto_publish": {"type": "boolean", "description": "Try to publish automatically in Lovable using Playwright MCP", "default": True},
            "published_slug": {"type": "string", "description": "Optional preferred Lovable subdomain slug", "default": ""},
            "workspace_name": {"type": "string", "description": "Optional Lovable workspace name to click after login", "default": ""},
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
        if bool(kwargs.get("auto_publish", True)):
            credentials = get_service_credentials(
                "loveable",
                channel=self._channel,
                chat_id=self._chat_id,
                user_id=getattr(self, "_user_id", "user"),
            )
            if credentials is None:
                result["notes"].append("To fully automate publish, first save Lovable credentials and configure the recommended Playwright MCP server.")
            else:
                try:
                    publish_flow = await self._run_loveable_publish_via_mcp(
                        build_url=result["url"],
                        username=credentials["username"],
                        password=credentials["password"],
                        publish_slug=str(kwargs.get("published_slug", "")),
                        workspace_name=str(kwargs.get("workspace_name", "")),
                        send_progress_updates=bool(kwargs.get("send_progress_updates", True)),
                    )
                    result["automation"] = publish_flow
                except Exception as exc:
                    result["notes"].append(f"Playwright MCP automation failed: {exc}")
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
                "description": "If true, send Lovable progress screenshots back to the active chat when Playwright MCP is configured.",
                "default": True,
            },
            "auto_publish": {"type": "boolean", "description": "Try to publish automatically in Lovable using Playwright MCP", "default": True},
            "published_slug": {"type": "string", "description": "Optional preferred Lovable subdomain slug", "default": ""},
            "workspace_name": {"type": "string", "description": "Optional Lovable workspace name to click after login", "default": ""},
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
        if bool(kwargs.get("auto_publish", True)):
            credentials = get_service_credentials(
                "loveable",
                channel=self._channel,
                chat_id=self._chat_id,
                user_id=getattr(self, "_user_id", "user"),
            )
            if credentials is None:
                result["notes"].append("To fully automate publish, first save Lovable credentials and configure the recommended Playwright MCP server.")
            else:
                try:
                    publish_flow = await self._run_loveable_publish_via_mcp(
                        build_url=result["url"],
                        username=credentials["username"],
                        password=credentials["password"],
                        publish_slug=str(kwargs.get("published_slug", "")),
                        workspace_name=str(kwargs.get("workspace_name", "")),
                        send_progress_updates=bool(kwargs.get("send_progress_updates", True)),
                    )
                    result["automation"] = publish_flow
                except Exception as exc:
                    result["notes"].append(f"Playwright MCP automation failed: {exc}")
        return json.dumps(result, indent=2)


class Base44CreateAppTool(_ProgressMixin):
    name = "base44_create_app"
    description = (
        "Create a Base44 app through the official Base44 MCP server. "
        "This follows Base44's docs-backed AI tooling flow."
    )
    parameters = {
        "type": "object",
        "properties": {
            "prompt": {"type": "string", "description": "Describe the app you want Base44 to build"},
        },
        "required": ["prompt"],
    }

    async def execute(self, **kwargs: Any) -> str:
        prompt = str(kwargs.get("prompt", "")).strip()
        self._notify("Asking Base44 MCP to create the app…")
        result = await base44_create_app(prompt)
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
        ConfigurePlatformMCPServersTool(channel=channel, chat_id=chat_id),
        save_tool,
        clear_tool,
        LoveableLandingPageTool(channel=channel, chat_id=chat_id),
        LoveableBuildUrlTool(channel=channel, chat_id=chat_id),
        Base44CreateAppTool(channel=channel, chat_id=chat_id),
        Base44DeployProjectTool(channel=channel, chat_id=chat_id),
    ]
