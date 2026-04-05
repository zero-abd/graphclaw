"""Official Loveable integration centered on Build with URL plus Playwright MCP automation."""

from __future__ import annotations

import webbrowser
from urllib.parse import quote


_BASE_URL = "https://lovable.dev/?autosubmit=true#"


def playwright_mcp_guide() -> dict:
    """Return the recommended Playwright MCP setup for Lovable browser automation."""
    return {
        "server": {
            "playwright": {
                "command": "npx",
                "args": ["@playwright/mcp@latest", "--headless"],
            }
        },
        "notes": [
            "Graphclaw can use Playwright MCP to log into Lovable, wait for generation, publish, and capture screenshots.",
            "Use configure_platform_mcp_servers to add the recommended Playwright MCP config automatically.",
        ],
    }


def _encode_images(images: list[str]) -> str:
    parts = []
    for image in images[:10]:
        cleaned = str(image or "").strip()
        if cleaned:
            parts.append(f"images={quote(cleaned, safe=':/?=&')}")
    return "&".join(parts)


def build_with_url(prompt: str, images: list[str] | None = None, open_browser: bool = False) -> dict:
    """Create a docs-supported Lovable Build with URL link.

    This opens Lovable and begins creating the app after the user logs in
    and picks a workspace. Graphclaw can then drive Lovable through a
    Playwright MCP server to publish and collect the shareable URL.
    """
    cleaned_prompt = str(prompt or "").strip()
    if not cleaned_prompt:
        raise ValueError("prompt is required")

    params = [f"prompt={quote(cleaned_prompt, safe='')}"]
    if images:
        image_params = _encode_images(images)
        if image_params:
            params.append(image_params)

    url = _BASE_URL + "&".join(params)
    if open_browser:
        webbrowser.open(url)

    return {
        "url": url,
        "kind": "loveable-build-url",
        "notes": [
            "Open the link while logged into Lovable to start generation automatically.",
            "After the project is ready, click Publish to get a live [published-url].lovable.app link.",
            "Lovable lets you set a custom subdomain during publish and add a custom domain later on paid plans.",
        ],
    }


def build_landing_page_url(
    brief: str,
    brand_name: str = "",
    primary_cta: str = "",
    style_notes: str = "",
    images: list[str] | None = None,
    open_browser: bool = False,
) -> dict:
    """Generate a polished landing-page Build with URL link for Lovable."""
    pieces = [
        "Create a polished responsive landing page website.",
        "Use modern spacing, strong hierarchy, and production-ready copy placeholders.",
        "Include a hero section, features section, testimonials, FAQ, and a strong CTA footer.",
    ]
    if brand_name:
        pieces.append(f"Brand/product name: {brand_name}.")
    if brief:
        pieces.append(f"Product brief: {brief}.")
    if primary_cta:
        pieces.append(f"Primary CTA: {primary_cta}.")
    if style_notes:
        pieces.append(f"Style notes: {style_notes}.")
    pieces.append("Make it launch-ready and visually impressive.")
    return build_with_url(" ".join(pieces), images=images, open_browser=open_browser)


def publish_guide() -> dict:
    """Return the official Lovable publish flow in a compact checklist."""
    return {
        "steps": [
            "Open your Lovable project and click Publish in the top-right corner.",
            "Choose or accept the published URL subdomain; Lovable defaults to [published-url].lovable.app.",
            "Review website access and metadata, then click Publish.",
            "Use Publish → Update for later changes, and add a custom domain later if needed.",
        ],
        "notes": [
            "Publishing deploys a snapshot; future changes are not live until you publish again.",
            "The published URL is separate from editor visibility.",
        ],
    }
