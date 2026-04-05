"""Web search and fetch tools."""
from __future__ import annotations
import re
from typing import Any


class WebSearchTool:
    name = "web_search"
    description = "Search the web using DuckDuckGo. Returns titles, URLs, and snippets."
    parameters = {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Search query"},
            "max_results": {"type": "integer", "description": "Max results", "default": 5},
        },
        "required": ["query"],
    }

    async def execute(self, **kwargs: Any) -> str:
        query = kwargs["query"]
        max_results = kwargs.get("max_results", 5)

        try:
            from duckduckgo_search import DDGS
            with DDGS() as ddg:
                results = list(ddg.text(query, max_results=max_results))
            if not results:
                return "No results found."
            lines = []
            for i, r in enumerate(results, 1):
                lines.append(f"{i}. {r.get('title', '')}")
                lines.append(f"   {r.get('href', '')}")
                lines.append(f"   {r.get('body', '')}")
                lines.append("")
            return "\n".join(lines)
        except ImportError:
            return "Error: duckduckgo-search not installed — pip install duckduckgo-search"
        except Exception as e:
            return f"Error searching: {e}"


class WebFetchTool:
    name = "web_fetch"
    description = "Fetch a URL and return its text content (HTML stripped)."
    parameters = {
        "type": "object",
        "properties": {
            "url": {"type": "string", "description": "URL to fetch"},
            "max_chars": {"type": "integer", "description": "Max characters to return", "default": 20000},
        },
        "required": ["url"],
    }

    async def execute(self, **kwargs: Any) -> str:
        url = kwargs["url"]
        max_chars = kwargs.get("max_chars", 20000)

        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                async with session.get(url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                    if resp.status != 200:
                        return f"Error: HTTP {resp.status}"
                    html = await resp.text()

            # Strip HTML tags
            text = re.sub(r'<script[^>]*>.*?</script>', '', html, flags=re.DOTALL)
            text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
            text = re.sub(r'<[^>]+>', ' ', text)
            text = re.sub(r'\s+', ' ', text).strip()

            if len(text) > max_chars:
                text = text[:max_chars] + f"\n... (truncated at {max_chars} chars)"
            return text
        except ImportError:
            return "Error: aiohttp not installed — pip install aiohttp"
        except Exception as e:
            return f"Error fetching URL: {e}"
