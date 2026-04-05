"""
Base44 skill — tools for deploying and managing apps on the Base44 platform.
Configure via env vars:
    BASE44_API_KEY   — your Base44 API key
    BASE44_BASE_URL  — API base URL (default: https://api.base44.com/v1)
"""

import os
import httpx

_BASE_URL = os.environ.get("BASE44_BASE_URL", "https://api.base44.com/v1")
_API_KEY = os.environ.get("BASE44_API_KEY", "")


def _headers() -> dict:
    if not _API_KEY:
        raise ValueError("BASE44_API_KEY env var is not set")
    return {"Authorization": f"Bearer {_API_KEY}", "Content-Type": "application/json"}


async def list_apps() -> dict:
    """List all apps in your Base44 account."""
    async with httpx.AsyncClient() as client:
        r = await client.get(f"{_BASE_URL}/apps", headers=_headers(), timeout=15.0)
        r.raise_for_status()
        return r.json()


async def get_app(app_id: str) -> dict:
    """Get details for a specific app by ID."""
    async with httpx.AsyncClient() as client:
        r = await client.get(f"{_BASE_URL}/apps/{app_id}", headers=_headers(), timeout=15.0)
        r.raise_for_status()
        return r.json()


async def deploy_app(app_id: str, branch: str = "main") -> dict:
    """Trigger a deployment for an app. Returns build/deploy job info."""
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{_BASE_URL}/apps/{app_id}/deploy",
            headers=_headers(),
            json={"branch": branch},
            timeout=30.0
        )
        r.raise_for_status()
        return r.json()


async def get_build_logs(app_id: str, deployment_id: str = "") -> dict:
    """Retrieve build logs. If no deployment_id, returns logs for latest deployment."""
    url = f"{_BASE_URL}/apps/{app_id}/logs"
    if deployment_id:
        url = f"{_BASE_URL}/apps/{app_id}/deployments/{deployment_id}/logs"
    async with httpx.AsyncClient() as client:
        r = await client.get(url, headers=_headers(), timeout=15.0)
        r.raise_for_status()
        return r.json()


async def get_app_status(app_id: str) -> dict:
    """Get current runtime status of an app (running, stopped, deploying, error)."""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{_BASE_URL}/apps/{app_id}/status", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()


async def get_env_vars(app_id: str) -> dict:
    """List all environment variables for an app (values may be masked)."""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{_BASE_URL}/apps/{app_id}/env", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()


async def update_env_vars(app_id: str, env_vars: dict) -> dict:
    """Set or update environment variables. Triggers a redeploy.
    Args:
        app_id: The app to update
        env_vars: dict of {KEY: value} pairs to set
    """
    async with httpx.AsyncClient() as client:
        r = await client.patch(
            f"{_BASE_URL}/apps/{app_id}/env",
            headers=_headers(),
            json={"variables": env_vars},
            timeout=30.0
        )
        r.raise_for_status()
        return r.json()


async def restart_app(app_id: str) -> dict:
    """Restart a running app without redeploying."""
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{_BASE_URL}/apps/{app_id}/restart", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()


async def rollback_app(app_id: str, deployment_id: str) -> dict:
    """Roll back an app to a previous deployment."""
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{_BASE_URL}/apps/{app_id}/rollback",
            headers=_headers(),
            json={"deployment_id": deployment_id},
            timeout=30.0
        )
        r.raise_for_status()
        return r.json()
