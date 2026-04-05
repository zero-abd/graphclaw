"""
Loveable skill — tools for building and managing apps via the Loveable platform.
Configure via env vars:
    LOVEABLE_API_KEY   — your Loveable API key
    LOVEABLE_BASE_URL  — API base URL (default: https://api.lovable.dev/v1)
"""

import os
import httpx

_BASE_URL = os.environ.get("LOVEABLE_BASE_URL", "https://api.lovable.dev/v1")
_API_KEY = os.environ.get("LOVEABLE_API_KEY", "")


def _headers() -> dict:
    if not _API_KEY:
        raise ValueError("LOVEABLE_API_KEY env var is not set")
    return {"Authorization": f"Bearer {_API_KEY}", "Content-Type": "application/json"}


async def list_projects() -> dict:
    """List all Loveable projects in your account."""
    async with httpx.AsyncClient() as client:
        r = await client.get(f"{_BASE_URL}/projects", headers=_headers(), timeout=15.0)
        r.raise_for_status()
        return r.json()


async def get_project(project_id: str) -> dict:
    """Get details for a specific project."""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{_BASE_URL}/projects/{project_id}", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()


async def create_project(name: str, description: str = "") -> dict:
    """Create a new Loveable project.
    Args:
        name: Project name
        description: Optional project description
    """
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{_BASE_URL}/projects",
            headers=_headers(),
            json={"name": name, "description": description},
            timeout=30.0
        )
        r.raise_for_status()
        return r.json()


async def publish_project(project_id: str) -> dict:
    """Publish/deploy a Loveable project to make it publicly accessible."""
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{_BASE_URL}/projects/{project_id}/publish",
            headers=_headers(),
            timeout=60.0
        )
        r.raise_for_status()
        return r.json()


async def get_project_status(project_id: str) -> dict:
    """Get the current build/deployment status of a project."""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{_BASE_URL}/projects/{project_id}/status", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()


async def get_project_url(project_id: str) -> dict:
    """Get the live URL for a published project."""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{_BASE_URL}/projects/{project_id}/url", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()


async def send_prompt(project_id: str, prompt: str) -> dict:
    """Send a natural language prompt to Loveable to modify the project.
    Args:
        project_id: The project to modify
        prompt: Natural language instruction (e.g. 'Add a dark mode toggle to the navbar')
    """
    async with httpx.AsyncClient() as client:
        r = await client.post(
            f"{_BASE_URL}/projects/{project_id}/chat",
            headers=_headers(),
            json={"message": prompt},
            timeout=120.0  # AI edits can take time
        )
        r.raise_for_status()
        return r.json()


async def get_chat_history(project_id: str) -> dict:
    """Get the chat/prompt history for a project."""
    async with httpx.AsyncClient() as client:
        r = await client.get(
            f"{_BASE_URL}/projects/{project_id}/chat", headers=_headers(), timeout=15.0
        )
        r.raise_for_status()
        return r.json()
