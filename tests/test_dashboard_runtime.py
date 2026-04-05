from __future__ import annotations

import importlib
import io
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from graphclaw import dashboard_runtime as _dashboard_runtime


dashboard_runtime = importlib.reload(_dashboard_runtime)


def test_dashboard_app_project_files_exist():
    project_root = REPO_ROOT / 'graphclaw' / 'dashboard_app'
    assert (project_root / 'jac.toml').exists()
    assert (project_root / 'main.jac').exists()
    assert (project_root / 'app.cl.jac').exists()


def test_with_repo_on_pythonpath_prepends_repo_root(monkeypatch):
    monkeypatch.setattr(dashboard_runtime, '_repo_root', lambda: Path('/tmp/repo'))
    env = dashboard_runtime._with_repo_on_pythonpath({'PYTHONPATH': '/tmp/existing'})
    assert env['PYTHONPATH'].split(os.pathsep)[0] == '/tmp/repo'


def test_dashboard_subprocess_env_enforces_utf8(monkeypatch):
    monkeypatch.setattr(dashboard_runtime, '_repo_root', lambda: Path('/tmp/repo'))
    env = dashboard_runtime._with_dashboard_subprocess_env({})
    assert env['PYTHONPATH'].split(os.pathsep)[0] == '/tmp/repo'
    assert env['PYTHONIOENCODING'] == 'utf-8'
    assert env['PYTHONUTF8'] == '1'


def test_dashboard_start_command_uses_python_utf8_on_windows(monkeypatch):
    monkeypatch.setattr(dashboard_runtime.os, 'name', 'nt')
    monkeypatch.setattr(dashboard_runtime.sys, 'executable', r'C:\Python313\python.exe')
    cmd = dashboard_runtime._dashboard_start_command(18789)
    assert cmd == [
        r'C:\Python313\python.exe',
        '-X',
        'utf8',
        '-m',
        'jaclang.jac0core.cli_boot',
        'start',
        '--dev',
        '--port',
        '18789',
    ]


def test_ensure_local_dashboard_launches_jac_from_dashboard_app(monkeypatch):
    monkeypatch.setattr(
        dashboard_runtime,
        '_dashboard_config',
        lambda: {'enabled': True, 'auto_open': False, 'host': '127.0.0.1', 'port': 18789},
    )
    monkeypatch.setattr(dashboard_runtime, '_dashboard_project_root', lambda: Path('/tmp/repo/graphclaw/dashboard_app'))
    monkeypatch.setattr(dashboard_runtime, '_repo_root', lambda: Path('/tmp/repo'))
    monkeypatch.setattr(dashboard_runtime, '_graphclaw_home', lambda: Path('/tmp/graphclaw-home'))
    monkeypatch.setattr(dashboard_runtime, '_cleanup_stale_state', lambda url: None)
    monkeypatch.setattr(dashboard_runtime, '_read_state', lambda: {})
    monkeypatch.setattr(dashboard_runtime, '_write_state', lambda payload: None)
    monkeypatch.setattr(dashboard_runtime.time, 'sleep', lambda _: None)
    monkeypatch.setattr(dashboard_runtime, '_log_path', lambda: Path('/tmp/graphclaw-home/logs/dashboard-server.log'))
    monkeypatch.setattr(Path, 'open', lambda self, *args, **kwargs: io.StringIO(), raising=False)
    monkeypatch.setattr(dashboard_runtime, '_jac_executable', lambda: 'jac')

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
    monkeypatch.setattr(dashboard_runtime, '_is_dashboard_reachable', lambda url, timeout=0.4: url == 'http://127.0.0.1:18789/')

    url = dashboard_runtime.ensure_local_dashboard(open_browser=False)

    assert url == 'http://127.0.0.1:18789/'
    assert recorded['cmd'] == ['jac', 'start', '--dev', '--port', '18789']
    assert recorded['cwd'] == '/tmp/repo/graphclaw/dashboard_app'
    assert recorded['env']['PYTHONPATH'].split(os.pathsep)[0] == '/tmp/repo'


def test_dashboard_client_sync_clears_stale_generated_client(tmp_path, monkeypatch):
    project_root = tmp_path / 'graphclaw' / 'dashboard_app'
    client_dir = project_root / '.jac' / 'client'
    configs_dir = client_dir / 'configs'
    configs_dir.mkdir(parents=True)
    (project_root / 'jac.toml').write_text(
        '[dependencies.npm]\nreact = "^18.2.0"\nreact-force-graph-2d = "^1.29.1"\n',
        encoding='utf-8',
    )
    (configs_dir / 'package.json').write_text(
        '{"dependencies": {"react": "^18.2.0"}}',
        encoding='utf-8',
    )

    monkeypatch.setattr(dashboard_runtime, '_dashboard_project_root', lambda: project_root)

    dashboard_runtime._ensure_dashboard_client_sync()

    assert not client_dir.exists()
