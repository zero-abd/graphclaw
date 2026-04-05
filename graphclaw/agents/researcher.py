"""Researcher agent — web research and knowledge synthesis."""
from __future__ import annotations
from graphclaw.agents.base import BaseAgent
from graphclaw.tools.web import WebSearchTool, WebFetchTool
from graphclaw.config.loader import load_config


class ResearcherAgent(BaseAgent):
    name = "researcher"
    system_prompt = (
        "You are a research specialist. Search the web, read pages, and synthesize findings "
        "into clear, factual summaries. Always cite sources. Cross-reference multiple sources "
        "when possible. Flag uncertainty or conflicting information."
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.tools = [WebSearchTool(), WebFetchTool()]
