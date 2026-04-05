# graphclaw/tools/web.jac

import from graphclaw.agents.base { AgentTool }

obj WebSearchTool(AgentTool) {
    has name: str = "web_search";
    has description: str = "Search the web using DuckDuckGo. Returns top results with titles, URLs, snippets.";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {
            "query": {"type": "string"},
            "max_results": {"type": "integer", "default": 8}
        },
        "required": ["query"]
    };
    def execute(params: dict) -> str {
        ::py::
        try:
            from duckduckgo_search import DDGS
            with DDGS() as ddgs:
                results = list(ddgs.text(params["query"], max_results=params.get("max_results", 8)))
            lines = []
            for r in results:
                lines.append(f"**{r.get('title','')}**\n{r.get('href','')}\n{r.get('body','')}\n")
            _result = "\n".join(lines) if lines else "[No results found]"
        except Exception as e:
            _result = f"[Search error: {e}]"
        ::py::
        return _result;
    }
}

obj WebFetchTool(AgentTool) {
    has name: str = "web_fetch";
    has description: str = "Fetch and extract readable text content from a URL.";
    has parameters_schema: dict = {
        "type": "object",
        "properties": {
            "url": {"type": "string"},
            "max_chars": {"type": "integer", "default": 8000}
        },
        "required": ["url"]
    };
    def execute(params: dict) -> str {
        ::py::
        import httpx
        try:
            resp = httpx.get(params["url"], timeout=15.0, follow_redirects=True,
                             headers={"User-Agent": "graphclaw/0.1"})
            resp.raise_for_status()
            try:
                from readability import Document
                doc = Document(resp.text)
                text = doc.summary()
                # Strip HTML tags
                import re
                text = re.sub(r"<[^>]+>", "", text)
            except Exception:
                text = resp.text
            max_chars = params.get("max_chars", 8000)
            _result = text[:max_chars].strip()
        except Exception as e:
            _result = f"[Fetch error: {e}]"
        ::py::
        return _result;
    }
}
