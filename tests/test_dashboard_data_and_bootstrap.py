from __future__ import annotations

import importlib
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from graphclaw.config import loader as loader_mod
from graphclaw.memory import backend as backend_mod
from graphclaw import dashboard as dashboard_mod


def _write_config(tmp_path: Path) -> Path:
    config_path = tmp_path / 'config.json'
    config_path.write_text(
        json.dumps(
            {
                'workspace': str(tmp_path / 'workspace'),
                'multi_user': False,
                'providers': {
                    'default_provider': 'openrouter',
                    'openrouter': {'api_key': '', 'base_url': 'https://openrouter.ai/api/v1'},
                    'anthropic': {'api_key': ''},
                    'openai': {'api_key': ''},
                },
                'channels': {
                    'telegram': {'enabled': False},
                    'discord': {'enabled': False},
                    'slack': {'enabled': False},
                    'email': {'enabled': False},
                    'whatsapp': {'enabled': False},
                },
                'dashboard': {'enabled': True, 'auto_open': False, 'host': '127.0.0.1', 'port': 18789},
            }
        ),
        encoding='utf-8',
    )
    return config_path


def test_bootstrap_creates_root_identity_memory(monkeypatch, tmp_path):
    config_path = _write_config(tmp_path)
    monkeypatch.setenv('GRAPHCLAW_CONFIG_PATH', str(config_path))
    monkeypatch.setenv('GRAPHCLAW_HOME', str(tmp_path / '.graphclaw-home'))

    loader = importlib.reload(loader_mod)
    backend = importlib.reload(backend_mod)

    profile = backend.get_profile()
    memories = backend._load_memories()

    assert profile['assistant_name'] == 'Graphclaw'
    assert profile['identity']
    assert profile['soul']
    assert profile['root_memory_id']

    system_keys = {memory.get('system_key') for memory in memories}
    assert {'assistant_root', 'assistant_name', 'assistant_identity', 'assistant_soul', 'assistant_dream_cadence'} <= system_keys

    root = next(memory for memory in memories if memory.get('system_key') == 'assistant_root')
    relationships = {item['relationship'] for item in root.get('relationships', [])}
    assert {'has_name', 'has_identity', 'has_soul', 'runs_dream_cycle'} <= relationships


def test_dashboard_overview_reports_skill_and_identity_state(monkeypatch, tmp_path):
    config_path = _write_config(tmp_path)
    monkeypatch.setenv('GRAPHCLAW_CONFIG_PATH', str(config_path))
    monkeypatch.setenv('GRAPHCLAW_HOME', str(tmp_path / '.graphclaw-home'))

    loader = importlib.reload(loader_mod)
    backend = importlib.reload(backend_mod)
    dashboard = importlib.reload(dashboard_mod)

    overview = dashboard.dashboard_overview()

    assert overview.root_ready is True
    assert overview.assistant_identity
    assert overview.assistant_soul
    assert overview.skill_count == overview.native_skill_count + overview.workflow_skill_count
    assert overview.skill_inventory_labels

    memory = dashboard.dashboard_memory()
    assert memory.core_node_labels
    assert memory.core_edge_count >= 4
