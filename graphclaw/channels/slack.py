"""Slack channel integration using slack-bolt."""
from __future__ import annotations
import asyncio
import sys
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.config.loader import load_config


async def start_slack_channel() -> bool:
    """Start the Slack bot in the background."""
    cfg = load_config()
    ch = cfg.channels.get("slack", {})
    bot_token = ch.get("bot_token", "")
    app_token = ch.get("app_token", "")
    if not bot_token or not app_token:
        print("[slack] bot_token and app_token required, skipping")
        return False

    try:
        from slack_bolt.async_app import AsyncApp
        from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler
    except ImportError:
        print(f"[slack] slack-bolt not installed — install it with: {sys.executable} -m pip install 'slack-bolt>=1.21.0'")
        return False

    app = AsyncApp(token=bot_token)

    @app.event("message")
    async def handle_message(event, say):
        if event.get("subtype"):  # ignore bot messages, edits, etc.
            return False
        text = event.get("text", "")
        if not text:
            return False

        user_id = event.get("user", "unknown")
        chat_id = event.get("channel", "unknown")
        thread_ts = event.get("thread_ts") or event.get("ts", "")

        bus.publish_inbound(InboundMessage(
            channel="slack",
            chat_id=chat_id,
            user_id=user_id,
            text=text,
            metadata={"thread_ts": thread_ts},
        ))

    # Outbound send loop
    async def _send_loop() -> None:
        from slack_sdk.web.async_client import AsyncWebClient
        client = AsyncWebClient(token=bot_token)
        q = bus.get_outbound_queue("slack")
        while True:
            msg: OutboundMessage = await q.get()
            try:
                thread_ts = msg.metadata.get("thread_ts")
                await client.chat_postMessage(
                    channel=msg.chat_id,
                    text=msg.text,
                    thread_ts=thread_ts,
                )
            except Exception as e:
                print(f"[slack] send error: {e}")

    asyncio.ensure_future(_send_loop())

    handler = AsyncSocketModeHandler(app, app_token)
    asyncio.ensure_future(handler.start_async())
    print("[slack] started socket mode")
    return True
