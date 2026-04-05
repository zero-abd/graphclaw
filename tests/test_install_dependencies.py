from pathlib import Path
import sys
import importlib

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from graphclaw import update_manager as _update_manager

update_manager = importlib.reload(_update_manager)


def test_update_manager_reinstalls_with_channel_extras(monkeypatch, tmp_path):
    fake_pip = tmp_path / "pip"
    fake_pip.write_text("", encoding="utf-8")

    recorded = {}

    def fake_run(cmd, check):
        recorded["cmd"] = cmd
        recorded["check"] = check

    monkeypatch.setattr(update_manager, "_pip_path", lambda: fake_pip)
    monkeypatch.setattr(update_manager, "source_dir", lambda: Path("/tmp/graphclaw"))
    monkeypatch.setattr(update_manager.subprocess, "run", fake_run)

    update_manager._reinstall_package()

    assert recorded["cmd"] == [
        str(fake_pip),
        "install",
        "-e",
        "/tmp/graphclaw[channels]",
        "-q",
    ]
    assert recorded["check"] is True


def test_install_sh_installs_channel_extras():
    install_sh = (REPO_ROOT / "install.sh").read_text(encoding="utf-8")

    assert 'pip install -e "${SOURCE_DIR}[channels]" -q 2>/dev/null' in install_sh
    assert "resolve_telegram_bot_username()" in install_sh
    assert 'Client onboarding link: https://t.me/$TG_USERNAME' in install_sh
    assert 'pairing approve telegram <code>' in install_sh
    assert 'Open https://t.me/$TG_USERNAME, press Start, then send me any message.' in install_sh


def test_install_ps1_installs_channel_extras():
    install_ps1 = (REPO_ROOT / "install.ps1").read_text(encoding="utf-8")

    assert '& $VenvPip install -e "${SourceDir}[channels]" 2>&1' in install_ps1
    assert "function Resolve-TelegramBotUsername" in install_ps1
    assert 'Client onboarding link: https://t.me/$script:TgUsername' in install_ps1
    assert 'pairing approve telegram <code>' in install_ps1
    assert 'Open https://t.me/$TgUsername, press Start, then send me any message.' in install_ps1
