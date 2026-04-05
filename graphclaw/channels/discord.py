"""Discord channel integration using discord.py."""
from __future__ import annotations
import asyncio
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.config.loader import load_config


async def start_discord_channel() -> None:
    """Start the Discord bot in the background."""
    cfg = load_config()
    ch = cfg.channels.get("discord", {})
    token = ch.get("bot_token", "")
    if not token:
        print("[discord] no bot_token configured, skipping")
        return

    try:
        import discord
    except ImportError:
        print("[discord] discord.py not installed — pip install discord.py")
        return

    intents = discord.Intents.default()
    intents.message_content = True
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready():
        print(f"[discord] logged in as {client.user}")

    @client.event
    async def on_message(message):
        if message.author == client.user:
            return
        if not message.content:
            return

        bus.publish_inbound(InboundMessage(
            channel="discord",
            chat_id=str(message.channel.id),
            user_id=str(message.author.id),
            text=message.content,
        ))

    # Outbound send loop
    async def _send_loop() -> None:
        await client.wait_until_ready()
        q = bus.get_outbound_queue("discord")
        while True:
            msg: OutboundMessage = await q.get()
            try:
                channel = client.get_channel(int(msg.chat_id))
                if channel:
                    # Discord 2000 char limit
                    text = msg.text
                    while text:
                        chunk, text = text[:2000], text[2000:]
                        await channel.send(chunk)
            except Exception as e:
                print(f"[discord] send error: {e}")

    asyncio.ensure_future(client.start(token))
    asyncio.ensure_future(_send_loop())
