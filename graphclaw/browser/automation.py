"""Browser automation helpers for screenshots and Loveable login."""
from __future__ import annotations

import asyncio
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Awaitable, Callable


async def _ensure_playwright_chromium() -> None:
    try:
        from playwright.async_api import async_playwright  # noqa: F401
        return
    except ImportError as exc:
        raise RuntimeError(
            "Playwright is not installed. Install it with `python -m pip install playwright`, "
            "then Graphclaw can auto-install Chromium on first screenshot run."
        ) from exc


def _screenshot_dir() -> Path:
    path = Path.home() / ".graphclaw" / "artifacts" / "screenshots"
    path.mkdir(parents=True, exist_ok=True)
    return path


async def _install_chromium_if_needed() -> None:
    process = await asyncio.create_subprocess_exec(
        sys.executable,
        "-m",
        "playwright",
        "install",
        "chromium",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        raise RuntimeError(
            f"Failed to install Chromium for Playwright: {(stderr or stdout).decode(errors='ignore').strip()}"
        )


async def _launch_browser():
    from playwright.async_api import Error, async_playwright

    playwright = await async_playwright().start()
    try:
        browser = await playwright.chromium.launch(headless=True)
    except Error:
        await playwright.stop()
        await _install_chromium_if_needed()
        playwright = await async_playwright().start()
        browser = await playwright.chromium.launch(headless=True)
    return playwright, browser


async def capture_url_screenshot(
    url: str,
    *,
    label: str = "page",
    wait_ms: int = 4000,
) -> str:
    await _ensure_playwright_chromium()
    playwright, browser = await _launch_browser()
    try:
        page = await browser.new_page(viewport={"width": 1440, "height": 1024})
        await page.goto(url, wait_until="domcontentloaded", timeout=90000)
        await page.wait_for_timeout(wait_ms)
        path = _screenshot_dir() / f"{label}-{next(tempfile._get_candidate_names())}.png"
        await page.screenshot(path=str(path), full_page=True)
        return str(path)
    finally:
        await browser.close()
        await playwright.stop()


async def _click_first(page, selectors: list[str]) -> bool:
    for selector in selectors:
        locator = page.locator(selector)
        try:
            if await locator.count() > 0 and await locator.first.is_visible():
                await locator.first.click()
                return True
        except Exception:
            continue
    return False


async def _fill_first(page, selectors: list[str], value: str) -> bool:
    for selector in selectors:
        locator = page.locator(selector)
        try:
            if await locator.count() > 0 and await locator.first.is_visible():
                await locator.first.fill(value)
                return True
        except Exception:
            continue
    return False


async def login_loveable_and_capture_progress(
    build_url: str,
    *,
    username: str,
    password: str,
    notify: Callable[[str], Awaitable[None]] | None = None,
    max_wait_ms: int = 25000,
) -> list[str]:
    await _ensure_playwright_chromium()
    playwright, browser = await _launch_browser()
    screenshots: list[str] = []
    try:
        page = await browser.new_page(viewport={"width": 1440, "height": 1024})
        if notify:
            await notify("Opening Lovable in a browser session…")
        await page.goto(build_url, wait_until="domcontentloaded", timeout=90000)
        await page.wait_for_timeout(3000)

        email_selectors = [
            'input[type="email"]',
            'input[name*="email" i]',
            'input[autocomplete="email"]',
        ]
        password_selectors = [
            'input[type="password"]',
            'input[name*="password" i]',
            'input[autocomplete="current-password"]',
        ]

        has_email = await _fill_first(page, email_selectors, username)
        if has_email:
            await _click_first(page, [
                'button:has-text("Continue")',
                'button:has-text("Next")',
                'button:has-text("Sign in")',
                'button:has-text("Log in")',
                'button[type="submit"]',
            ])
            await page.wait_for_timeout(1500)

        has_password = await _fill_first(page, password_selectors, password)
        if has_password:
            await _click_first(page, [
                'button:has-text("Sign in")',
                'button:has-text("Log in")',
                'button:has-text("Continue")',
                'button[type="submit"]',
            ])
            await page.wait_for_timeout(4000)

        path1 = _screenshot_dir() / f"loveable-login-{next(tempfile._get_candidate_names())}.png"
        await page.screenshot(path=str(path1), full_page=True)
        screenshots.append(str(path1))
        if notify:
            await notify("Captured a Lovable progress screenshot after login/startup.")

        await page.wait_for_timeout(min(max_wait_ms, 12000))
        path2 = _screenshot_dir() / f"loveable-progress-{next(tempfile._get_candidate_names())}.png"
        await page.screenshot(path=str(path2), full_page=True)
        screenshots.append(str(path2))
        if notify:
            await notify("Captured a second Lovable progress screenshot.")
        return screenshots
    finally:
        await browser.close()
        await playwright.stop()
