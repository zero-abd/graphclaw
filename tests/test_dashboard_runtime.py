from __future__ import annotations

import importlib
import io
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from graphclaw import dashboard_data
from graphclaw import dashboard_runtime as _dashboard_runtime
from graphclaw import dashboard_server


dashboard_runtime = importlib.reload(_dashboard_runtime)


def test_dashboard_data_helpers_are_importable():
    assert callable(dashboard_data.dashboard_overview)
    assert callable(dashboard_data.dashboard_memory)
    assert callable(dashboard_data.dashboard_save_settings)


def test_render_dashboard_html_contains_control_room(monkeypatch):
    monkeypatch.setattr(
        dashboard_server,
        'dashboard_overview',
        lambda: dashboard_data.OverviewResponse(assistant_name='Graphclaw', workspace='/tmp/workspace'),
    )
    monkeypatch.setattr(
        dashboard_server,
        'dashboard_memory',
        lambda: dashboard_data.MemoryResponse(profile_json='{}'),
    )

    html = dashboard_server.render_dashboard_html()

    assert 'Graphclaw Control' in html
    assert 'Control Room' in html
    assert '/dashboard.css' in html


def test_with_repo_on_pythonpath_prepends_repo_root(monkeypatch):
    monkeypatch.setattr(dashboard_runtime, '_repo_root', lambda: Path('/tmp/repo'))
    env = dashboard_runtime._with_repo_on_pythonpath({'PYTHONPATH': '/tmp/existing'})
    assert env['PYTHONPATH'].split(os.pathsep)[0] == '/tmp/repo'


def test_ensure_local_dashboard_launches_python_dashboard_server(monkeypatch):
    monkeypatch.setattr(
        dashboard_runtime,
        '_dashboard_config',
        lambda: {'enabled': True, 'auto_open': False, 'host': '127.0.0.1', 'port': 18789},
    )
    monkeypatch.setattr(dashboard_runtime, '_repo_root', lambda: Path('/tmp/repo'))
    monkeypatch.setattr(dashboard_runtime, '_graphclaw_home', lambda: Path('/tmp/graphclaw-home'))
    monkeypatch.setattr(dashboard_runtime, '_cleanup_stale_state', lambda url: None)
    monkeypatch.setattr(dashboard_runtime, '_read_state', lambda: {})
    monkeypatch.setattr(dashboard_runtime, '_write_state', lambda payload: None)
    monkeypatch.setattr(dashboard_runtime.time, 'sleep', lambda _: None)
    monkeypatch.setattr(dashboard_runtime, '_log_path', lambda: Path('/tmp/graphclaw-home/logs/dashboard-server.log'))
    monkeypatch.setattr(Path, 'open', lambda self, *args, **kwargs: io.StringIO(), raising=False)

    class FakeProc:
        pid = 4242
        def poll(self):
            return None
        def terminate(self):
            return None
        def wait(self, timeout=None):
            return 0
        def kill(self):
            return None

    recorded = {}
    def fake_popen(cmd, cwd, env, stdout, stderr, text):
        recorded['cmd'] = cmd
        recorded['cwd'] = cwd
        recorded['env'] = env
        return FakeProc()

    monkeypatch.setattr(dashboard_runtime.subprocess, 'Popen', fake_popen)
    monkeypatch.setattr(dashboard_runtime, '_is_dashboard_reachable', lambda url, timeout=0.4: url.endswith('/'))

    url = dashboard_runtime.ensure_local_dashboard(open_browser=False)

    assert url == 'http://127.0.0.1:18789/'
    assert recorded['cmd'][:3] == [sys.executable, '-m', 'graphclaw.dashboard_server']
    assert recorded['env']['PYTHONPATH'].split(os.pathsep)[0] == '/tmp/repo'
