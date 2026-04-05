import asyncio
import sys
import types
import importlib
from pathlib import Path
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from graphclaw.channels import auth as _auth_mod
from graphclaw.channels import discord as _discord_mod
from graphclaw.channels import telegram as _telegram_mod

auth_mod = importlib.reload(_auth_mod)
discord_mod = importlib.reload(_discord_mod)
telegram_mod = importlib.reload(_telegram_mod)


class DummyQueue:
    async def get(self):  # pragma: no cover - scheduled send loops are closed before execution
        raise asyncio.CancelledError


class FakeBus:
    def __init__(self):
        self.inbound = []
        self.outbound = []
        self.queue = DummyQueue()

    def publish_inbound(self, msg):
        self.inbound.append(msg)

    def publish_outbound(self, msg):
        self.outbound.append(msg)

    def get_outbound_queue(self, channel=None):
        return self.queue


class DummyFilter:
    def __and__(self, other):
        return self

    def __invert__(self):
        return self


class FakeTelegramMessageHandler:
    def __init__(self, _filters, callback):
        self.callback = callback


class FakeTelegramBot:
    def __init__(self):
        self.sent_messages = []

    async def get_me(self):
        return SimpleNamespace(id="bot-id", username="graphclawbot")

    async def send_message(self, **kwargs):
        self.sent_messages.append(kwargs)


class FakeTelegramUpdater:
    async def start_polling(self, **kwargs):
        return None


class FakeTelegramApp:
    def __init__(self):
        self.bot = FakeTelegramBot()
        self.updater = FakeTelegramUpdater()
        self.handlers = []

    def add_handler(self, handler):
        self.handlers.append(handler)

    async def initialize(self):
        return None

    async def start(self):
        return None


class FakeTelegramApplicationBuilder:
    def __init__(self, app):
        self.app = app

    def token(self, token):
        self.token_value = token
        return self

    def build(self):
        return self.app


class FakeLogger:
    def __init__(self):
        self.levels = []

    def setLevel(self, level):
        self.levels.append(level)

class FakeDiscordSelfUser:
    def __init__(self, user_id="self-user"):
        self.id = user_id

    def mentioned_in(self, message):
        return any(getattr(mention, "id", None) == self.id for mention in getattr(message, "mentions", []))


class FakeDiscordChannel:
    def __init__(self, channel_id, name="general"):
        self.id = channel_id
        self.name = name
        self.sent_messages = []

    async def send(self, text):
        self.sent_messages.append(text)


class FakeDiscordClient:
    def __init__(self, intents):
        self.intents = intents
        self.user = FakeDiscordSelfUser()
        self._handlers = {}
        self._channels = {}

    def event(self, fn):
        self._handlers[fn.__name__] = fn
        return fn

    async def wait_until_ready(self):
        return None

    def get_channel(self, channel_id):
        return self._channels.get(channel_id)

    async def start(self, token):
        return None


class FakeDiscordIntents:
    def __init__(self):
        self.message_content = False

    @classmethod
    def default(cls):
        return cls()


class FakeDiscordModule:
    def __init__(self, client):
        self.Intents = FakeDiscordIntents
        self._client = client

    def Client(self, intents):
        self._client.intents = intents
        return self._client


class ClosedTask(SimpleNamespace):
    def cancel(self):
        return None


def _close_scheduled(coro):
    if hasattr(coro, "close"):
        coro.close()
    return ClosedTask()


def _install_fake_telegram(monkeypatch, cfg):
    fake_bus = FakeBus()
    fake_app = FakeTelegramApp()
    fake_ext = types.ModuleType("telegram.ext")
    fake_ext.ApplicationBuilder = lambda: FakeTelegramApplicationBuilder(fake_app)
    fake_ext.MessageHandler = FakeTelegramMessageHandler
    fake_ext.filters = SimpleNamespace(TEXT=DummyFilter(), COMMAND=DummyFilter())
    fake_ext.ContextTypes = SimpleNamespace(DEFAULT_TYPE=object)
    fake_telegram = types.ModuleType("telegram")
    fake_telegram.Update = object
    monkeypatch.setitem(sys.modules, "telegram", fake_telegram)
    monkeypatch.setitem(sys.modules, "telegram.ext", fake_ext)
    monkeypatch.setattr(telegram_mod, "load_config", lambda: cfg)
    monkeypatch.setattr(telegram_mod, "bus", fake_bus)
    monkeypatch.setattr(telegram_mod.asyncio, "ensure_future", _close_scheduled)
    return fake_bus, fake_app


def _install_fake_discord(monkeypatch, cfg):
    fake_bus = FakeBus()
    fake_client = FakeDiscordClient(FakeDiscordIntents.default())
    fake_discord = FakeDiscordModule(fake_client)
    monkeypatch.setitem(sys.modules, "discord", fake_discord)
    monkeypatch.setattr(discord_mod, "load_config", lambda: cfg)
    monkeypatch.setattr(discord_mod, "bus", fake_bus)
    monkeypatch.setattr(discord_mod.asyncio, "ensure_future", _close_scheduled)
    return fake_bus, fake_client


def _telegram_update(
    *,
    user_id="42",
    chat_id="99",
    text="hello",
    chat_type="private",
    title="",
    username="user42",
    full_name="User 42",
    mention_bot=False,
    reply_to_bot=False,
):
    entities = []
    if mention_bot:
        text = text if "@graphclawbot" in text else f"@graphclawbot {text}"
        entities = [SimpleNamespace(type="mention", offset=0, length=len("@graphclawbot"))]
    reply_message = None
    if reply_to_bot:
        reply_message = SimpleNamespace(from_user=SimpleNamespace(id="bot-id"))
    message = SimpleNamespace(text=text, entities=entities, reply_to_message=reply_message)
    chat = SimpleNamespace(id=chat_id, type=chat_type, title=title)
    user = SimpleNamespace(id=user_id, username=username, full_name=full_name)
    return SimpleNamespace(message=message, effective_user=user, effective_chat=chat)


def _discord_message(
    *,
    author,
    content="hello",
    channel_id="9001",
    channel_name="general",
    guild_id=None,
    mentions=None,
    reply_to_bot=False,
):
    channel = FakeDiscordChannel(int(channel_id), name=channel_name)
    guild = None if guild_id is None else SimpleNamespace(id=int(guild_id))
    reference = None
    if reply_to_bot:
        reference = SimpleNamespace(resolved=SimpleNamespace(author=FakeDiscordSelfUser()))
    return SimpleNamespace(
        author=author,
        content=content,
        channel=channel,
        guild=guild,
        mentions=mentions or [],
        reference=reference,
    )


def test_auth_manager_persists_pending_and_approved_dm_state(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))

    manager = auth_mod.ChannelAuthManager(
        "telegram",
        {
            "owner_ids": ["owner-1"],
            "dm_policy": "pairing",
            "allow_from": [],
        },
    )

    pending = manager.evaluate(
        auth_mod.AuthEvent(
            channel="telegram",
            user_id="new-user",
            chat_id="chat-7",
            text="hello",
            is_direct=True,
            username="newbie",
            display_name="New User",
        )
    )
    assert pending.allow_publish is False
    assert pending.metadata["auth_status"] == "pending"
    code = pending.metadata["pairing_code"]
    assert manager.pairing_path.exists()

    approval = manager.evaluate(
        auth_mod.AuthEvent(
            channel="telegram",
            user_id="owner-1",
            chat_id="owner-chat",
            text=f"pairing approve {code}",
            is_direct=True,
        )
    )
    assert approval.metadata["auth_status"] == "approved"
    assert approval.notifications[0].chat_id == "chat-7"
    assert manager.allow_path.exists()
    assert "new-user" in manager.allow_path.read_text(encoding="utf-8")

    fresh_manager = auth_mod.ChannelAuthManager(
        "telegram",
        {
            "owner_ids": ["owner-1"],
            "dm_policy": "pairing",
            "allow_from": [],
        },
    )
    approved = fresh_manager.evaluate(
        auth_mod.AuthEvent(
            channel="telegram",
            user_id="new-user",
            chat_id="chat-7",
            text="hello again",
            is_direct=True,
        )
    )
    assert approved.allow_publish is True
    assert approved.metadata["auth_status"] == "approved"


def test_startup_warnings_point_to_local_cli_when_no_owner_ids(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))

    manager = auth_mod.ChannelAuthManager(
        "telegram",
        {
            "dm_policy": "pairing",
            "allow_from": [],
            "owner_ids": [],
        },
    )

    warnings = manager.startup_warnings()

    assert any("pairing approve telegram <code>" in warning for warning in warnings)
    assert any("direct messages still work" in warning for warning in warnings)
    assert not any("No owner_ids are configured yet" in warning for warning in warnings)
    assert not any("owner_ids (or allow_from)" in warning for warning in warnings)


def test_pairing_prompt_prefers_local_cli_without_owner_ids(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))

    manager = auth_mod.ChannelAuthManager(
        "telegram",
        {
            "dm_policy": "pairing",
            "allow_from": [],
            "owner_ids": [],
        },
    )

    pending = manager.evaluate(
        auth_mod.AuthEvent(
            channel="telegram",
            user_id="new-user",
            chat_id="chat-7",
            text="hello",
            is_direct=True,
        )
    )

    assert pending.allow_publish is False
    assert any("pairing approve telegram" in response for response in pending.responses)
    assert not any("No owner_ids are configured yet" in response for response in pending.responses)


def test_telegram_allowlist_blocks_unlisted_sender(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    cfg = SimpleNamespace(channels={"telegram": {"bot_token": "token", "allow_from": ["approved-user"]}})
    fake_bus, fake_app = _install_fake_telegram(monkeypatch, cfg)

    assert asyncio.run(telegram_mod.start_telegram_channel()) is True

    handler = fake_app.handlers[0].callback
    asyncio.run(handler(_telegram_update(user_id="stranger"), None))

    assert fake_bus.inbound == []
    assert fake_app.bot.sent_messages


def test_telegram_pairing_policy_prompts_unknown_sender_before_dispatch(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    cfg = SimpleNamespace(
        channels={
            "telegram": {
                "bot_token": "token",
                "allow_from": [],
                "dm_policy": "pairing",
                "owner_ids": ["owner-1"],
            }
        }
    )
    fake_bus, fake_app = _install_fake_telegram(monkeypatch, cfg)

    assert asyncio.run(telegram_mod.start_telegram_channel()) is True

    handler = fake_app.handlers[0].callback
    asyncio.run(handler(_telegram_update(user_id="unknown-dm"), None))

    assert fake_bus.inbound == []
    assert fake_app.bot.sent_messages
    assert any("Pairing code:" in item["text"] for item in fake_app.bot.sent_messages)


def test_telegram_startup_prints_first_use_instructions_and_quiets_noisy_logs(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("HOME", str(tmp_path))
    cfg = SimpleNamespace(
        channels={
            "telegram": {
                "bot_token": "token",
                "allow_from": [],
                "dm_policy": "pairing",
                "owner_ids": [],
            }
        }
    )
    fake_bus, fake_app = _install_fake_telegram(monkeypatch, cfg)
    fake_loggers = {}
    real_get_logger = telegram_mod.logging.getLogger

    def fake_get_logger(name=None):
        if name not in {"httpx", "httpcore", "telegram", "telegram.ext"}:
            return real_get_logger(name)
        logger = fake_loggers.get(name)
        if logger is None:
            logger = FakeLogger()
            fake_loggers[name] = logger
        return logger

    monkeypatch.setattr(telegram_mod.logging, "getLogger", fake_get_logger)

    assert asyncio.run(telegram_mod.start_telegram_channel()) is True

    out = capsys.readouterr().out
    assert fake_bus.inbound == []
    assert "https://t.me/graphclawbot" in out
    assert "press Start in Telegram, then send any message" in out
    assert "pairing approve telegram <code>" in out
    for logger_name in ("httpx", "httpcore", "telegram", "telegram.ext"):
        assert fake_loggers[logger_name].levels[-1] == telegram_mod.logging.WARNING


def test_discord_ignores_self_messages(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    cfg = SimpleNamespace(channels={"discord": {"bot_token": "token"}})
    fake_bus, fake_client = _install_fake_discord(monkeypatch, cfg)

    assert asyncio.run(discord_mod.start_discord_channel()) is True

    message = _discord_message(author=fake_client.user)
    asyncio.run(fake_client._handlers["on_message"](message))

    assert fake_bus.inbound == []


def test_discord_dm_pairing_blocks_unknown_sender_until_approved(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    cfg = SimpleNamespace(
        channels={
            "discord": {
                "bot_token": "token",
                "dm_policy": "pairing",
                "allow_from": [],
                "owner_ids": ["owner-1"],
            }
        }
    )
    fake_bus, fake_client = _install_fake_discord(monkeypatch, cfg)

    assert asyncio.run(discord_mod.start_discord_channel()) is True

    stranger = SimpleNamespace(id="stranger", bot=False, name="stranger", display_name="Stranger", global_name="Stranger")
    message = _discord_message(author=stranger, guild_id=None)
    asyncio.run(fake_client._handlers["on_message"](message))

    assert fake_bus.inbound == []
    assert message.channel.sent_messages
    assert any("Pairing code:" in text for text in message.channel.sent_messages)


def test_discord_guild_messages_default_to_safe_drop_without_allowlist_or_mention(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    cfg = SimpleNamespace(
        channels={
            "discord": {
                "bot_token": "token",
                "group_policy": "allowlist",
                "guilds": {},
            }
        }
    )
    fake_bus, fake_client = _install_fake_discord(monkeypatch, cfg)

    assert asyncio.run(discord_mod.start_discord_channel()) is True

    member = SimpleNamespace(id="member-1", bot=False, name="member1", display_name="Member 1", global_name="Member 1")
    message = _discord_message(author=member, guild_id="12345", mentions=[])
    asyncio.run(fake_client._handlers["on_message"](message))

    assert fake_bus.inbound == []
    assert message.channel.sent_messages == []


def test_main_jac_keeps_local_cli_available_when_channels_start():
    main_jac = Path("graphclaw/main.jac").read_text(encoding="utf-8")

    assert "interactive_cli_enabled = bool(sys.stdin and sys.stdin.isatty())" in main_jac
    assert 'print("[graphclaw] local CLI enabled — use it for chat or pairing commands (Ctrl+C to exit):")' in main_jac
