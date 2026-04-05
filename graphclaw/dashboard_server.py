"""Simple local-only single-user dashboard server."""
from __future__ import annotations

import argparse
from html import escape
from pathlib import Path

from aiohttp import web

from graphclaw.dashboard_data import dashboard_memory, dashboard_overview


def _css_path() -> Path:
    return Path(__file__).with_name("dashboard.css")


def _list_items(values: list[str]) -> str:
    if not values:
        return '<div class="list-item"><div class="list-item-meta">None yet</div></div>'
    return "".join(
        f'<div class="list-item"><div class="list-item-title">{escape(value)}</div></div>'
        for value in values
    )


def _node_cards(memory) -> str:
    if not memory.nodes:
        return '<div class="notice">No persisted memory nodes yet.</div>'
    return "".join(
        '<div class="node-card">'
        f'<div class="node-kind">{escape(node.kind)}</div>'
        f'<div class="node-title">{escape(node.label)}</div>'
        f'<div class="list-item-meta">ID: {escape(node.id)}</div>'
        '</div>'
        for node in memory.nodes[:40]
    )


def _edge_items(memory) -> str:
    if not memory.edges:
        return '<div class="notice">No graph edges yet.</div>'
    return "".join(
        '<div class="edge-item">'
        f'<strong>{escape(edge.label)}</strong>'
        f'<div class="list-item-meta">{escape(edge.source)} → {escape(edge.target)}</div>'
        '</div>'
        for edge in memory.edges[:50]
    )


def render_dashboard_html() -> str:
    overview = dashboard_overview()
    memory = dashboard_memory()
    update_text = 'Update available' if overview.update_available else 'Stable'
    update_tone = 'warn' if overview.update_available else 'good'
    dream_text = 'enabled' if overview.dream_enabled else 'disabled'
    return f"""<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
    <title>Graphclaw Control</title>
    <link rel=\"stylesheet\" href=\"/dashboard.css\" />
  </head>
  <body>
    <div class=\"dashboard-shell\">
      <aside class=\"sidebar\">
        <div class=\"brand-pill\">Graphclaw Control</div>
        <h1 class=\"brand-title\">{escape(overview.assistant_name)}</h1>
        <p class=\"brand-subtitle\">Single-user local dashboard for runtime visibility, config inspection, and graph memory browsing.</p>
        <div class=\"sidebar-footer\">
          <div class=\"list-item-title\">Local dashboard</div>
          <div class=\"list-item-meta\">This local dashboard avoids the Jac client dev server so single-user installs still get a working web UI.</div>
        </div>
      </aside>
      <main class=\"main\">
        <div class=\"stack\">
          <div class=\"page-header\">
            <div>
              <h1>Control Room</h1>
              <p>Monitor runtime health, channels, sessions, update state, and persisted memory from one place.</p>
            </div>
            <div class=\"header-actions\">
              <span class=\"status-pill {update_tone}\">{escape(update_text)}</span>
              <span class=\"status-pill info\">{escape(overview.version)}</span>
            </div>
          </div>
          <div class=\"stats-grid\">
            <section class=\"card pad\"><span class=\"status-pill info\">Memory</span><div class=\"stat-card-value\">{overview.memory_count}</div><div class=\"stat-card-meta\">Live persisted memories</div></section>
            <section class=\"card pad\"><span class=\"status-pill good\">Sessions</span><div class=\"stat-card-value\">{overview.session_count}</div><div class=\"stat-card-meta\">Tracked chat sessions</div></section>
            <section class=\"card pad\"><span class=\"status-pill warn\">Skills</span><div class=\"stat-card-value\">{overview.skill_count}</div><div class=\"stat-card-meta\">Installed runtime skills</div></section>
            <section class=\"card pad\"><span class=\"status-pill info\">Provider</span><div class=\"stat-card-value\">{escape(overview.default_provider)}</div><div class=\"stat-card-meta\">{escape(overview.default_model)}</div></section>
          </div>
          <div class=\"layout-grid\">
            <div class=\"stack\">
              <section class=\"card pad\"><div class=\"card-header\"><div><h2>Runtime &amp; Update</h2><p class=\"brand-subtitle\">Current workspace and update status</p></div></div><div class=\"list-grid\"><div class=\"notice\">Workspace: {escape(overview.workspace)}<br/>Current commit: {escape(overview.current_commit)}<br/>Latest main: {escape(overview.latest_commit)}</div>{_list_items(overview.channel_summary)}</div></section>
              <section class=\"card pad\"><div class=\"card-header\"><div><h2>Recent Sessions</h2><p class=\"brand-subtitle\">Latest stored conversations</p></div></div><div class=\"list-grid\">{_list_items(overview.recent_session_labels)}</div></section>
            </div>
            <div class=\"stack\">
              <section class=\"card pad\"><div class=\"card-header\"><div><h2>Configuration Snapshot</h2><p class=\"brand-subtitle\">Read-only first version</p></div></div><div class=\"list-grid\"><div class=\"list-item\"><div class=\"list-item-title\">Assistant name</div><div class=\"list-item-meta\">{escape(overview.assistant_name)}</div></div><div class=\"list-item\"><div class=\"list-item-title\">Default provider</div><div class=\"list-item-meta\">{escape(overview.default_provider)}</div></div><div class=\"list-item\"><div class=\"list-item-title\">Default model</div><div class=\"list-item-meta\">{escape(overview.default_model)}</div></div><div class=\"list-item\"><div class=\"list-item-title\">Dream maintenance</div><div class=\"list-item-meta\">{dream_text} · every {overview.dream_interval_hours}h</div></div></div></section>
              <section class=\"card pad\"><div class=\"card-header\"><div><h2>Skills Snapshot</h2><p class=\"brand-subtitle\">Installed skills visible to the runtime</p></div></div><div class=\"list-grid\">{_list_items(overview.skill_labels)}</div></section>
            </div>
          </div>
          <div class=\"memory-grid\">
            <section class=\"card pad\"><div class=\"card-header\"><div><h2>Node Explorer</h2><p class=\"brand-subtitle\">Profile, memories, sessions, and turns</p></div></div><div class=\"node-grid\">{_node_cards(memory)}</div></section>
            <div class=\"stack\">
              <section class=\"card pad\"><div class=\"card-header\"><div><h2>Relationship Feed</h2><p class=\"brand-subtitle\">Derived from persisted memory edges</p></div></div><div class=\"edge-list\">{_edge_items(memory)}</div></section>
              <section class=\"card pad\"><div class=\"card-header\"><div><h2>Profile State</h2><p class=\"brand-subtitle\">Persisted identity and assistant preferences</p></div></div><pre class=\"textarea\">{escape(memory.profile_json)}</pre></section>
            </div>
          </div>
        </div>
      </main>
    </div>
  </body>
</html>"""


async def handle_dashboard(_request: web.Request) -> web.Response:
    return web.Response(text=render_dashboard_html(), content_type='text/html')


async def handle_css(_request: web.Request) -> web.Response:
    return web.FileResponse(_css_path())


async def handle_overview(_request: web.Request) -> web.Response:
    return web.json_response(dashboard_overview().__dict__)


async def handle_memory(_request: web.Request) -> web.Response:
    payload = dashboard_memory()
    return web.json_response({
        'assistant_name': payload.assistant_name,
        'profile_json': payload.profile_json,
        'node_count': payload.node_count,
        'edge_count': payload.edge_count,
        'nodes': [node.__dict__ for node in payload.nodes],
        'edges': [edge.__dict__ for edge in payload.edges],
    })


def build_app() -> web.Application:
    app = web.Application()
    app.router.add_get('/', handle_dashboard)
    app.router.add_get('/dashboard.css', handle_css)
    app.router.add_get('/api/overview', handle_overview)
    app.router.add_get('/api/memory', handle_memory)
    return app


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Run the local Graphclaw dashboard server.')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=18789)
    args = parser.parse_args(argv)
    web.run_app(build_app(), host=args.host, port=args.port)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
