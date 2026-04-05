"""Discord channel integration using discord.py."""
from __future__ import annotations
import asyncio
from pathlib import Path
import sys
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.channels.auth import AuthEvent, ChannelAuthManager
from graphclaw.config.loader import load_config


async def start_discord_channel() -> bool:
    """Start the Discord bot in the background."""
    cfg = load_config()
    ch = cfg.channels.get("discord", {})
    token = ch.get("bot_token", "")
    if not token:
        print("[discord] no bot_token configured, skipping")
        return False

    try:
        import discord
    except ImportError:
        print(f"[discord] discord.py not installed — install it with: {sys.executable} -m pip install 'discord.py>=2.4.0'")
        return False

    auth = ChannelAuthManager("discord", ch)
    for warning in auth.startup_warnings():
        print(f"[discord] {warning}")

    intents = discord.Intents.default()
    intents.message_content = True
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready():
        print(f"[discord] logged in as {client.user}")

    @client.event
    async def on_message(message):
        if message.author == client.user:
            return None
        if not message.content:
            return None

        is_direct = message.guild is None
        reply_to_bot = bool(
            message.reference
            and getattr(message.reference, "resolved", None)
            and getattr(message.reference.resolved, "author", None) == client.user
        )
        is_mentioned = reply_to_bot or client.user.mentioned_in(message)
        decision = auth.evaluate(
            AuthEvent(
                channel="discord",
                user_id=str(message.author.id),
                chat_id=str(message.channel.id),
                text=message.content,
                is_direct=is_direct,
                username=str(getattr(message.author, "name", "")),
                display_name=str(getattr(message.author, "display_name", "") or getattr(message.author, "global_name", "")),
                is_mentioned=is_mentioned,
                mention_detection_available=client.user is not None,
                channel_name=str(getattr(message.channel, "name", "")),
                guild_id=str(message.guild.id) if message.guild else "",
                group_id=str(message.channel.id),
            )
        )

        for response in decision.responses:
            try:
                await message.channel.send(response)
            except Exception as exc:
                print(f"[discord] auth reply error: {exc}")
        for notification in decision.notifications:
            try:
                channel = client.get_channel(int(notification.chat_id))
                if channel is None:
                    channel = await client.fetch_channel(int(notification.chat_id))
                if channel:
                    await channel.send(notification.text)
            except Exception as exc:
                print(f"[discord] auth notify error: {exc}")
        if not decision.allow_publish:
            return None

        bus.publish_inbound(InboundMessage(
            channel="discord",
            chat_id=str(message.channel.id),
            user_id=str(message.author.id),
            text=message.content,
            metadata=decision.metadata,
        ))

    # Outbound send loop
    async def _send_loop() -> None:
        await client.wait_until_ready()
        q = bus.get_outbound_queue("discord")
        while True:
            msg: OutboundMessage = await q.get()
            try:
                channel = client.get_channel(int(msg.chat_id))
                if channel is None:
                    channel = await client.fetch_channel(int(msg.chat_id))
                if channel:
                    files = []
                    for media_path in msg.media or []:
                        path = Path(media_path)
                        if path.exists():
                            files.append(discord.File(str(path)))
                    text = msg.text
                    if files:
                        await channel.send(content=text[:2000] if text else None, files=files[:10])
                    else:
                        while text:
                            chunk, text = text[:2000], text[2000:]
                            await channel.send(chunk)
            except Exception as e:
                print(f"[discord] send error: {e}")

    asyncio.ensure_future(client.start(token))
    asyncio.ensure_future(_send_loop())
    return True
