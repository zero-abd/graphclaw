# graphclaw/channels/discord.jac

import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage }
import from graphclaw.config.loader { load_config }

def start_discord_channel() {
    ::py::
    import asyncio, discord

    cfg = load_config()
    dc = cfg.channels.discord
    if not dc.enabled or not dc.bot_token:
        return

    intents = discord.Intents.default()
    intents.message_content = True
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready():
        print(f"[discord] logged in as {client.user}")
        asyncio.create_task(send_loop())

    @client.event
    async def on_message(message: discord.Message):
        if message.author == client.user:
            return
        if dc.guild_ids and message.guild and message.guild.id not in dc.guild_ids:
            return

        inbound = InboundMessage(
            channel="discord",
            chat_id=str(message.channel.id),
            user_id=str(message.author.id),
            text=message.content,
            raw={"guild_id": message.guild.id if message.guild else None,
                 "message_id": message.id}
        )
        bus.publish_inbound(inbound)

    async def send_loop():
        q = bus.get_outbound_queue()
        while True:
            out: OutboundMessage = await q.get()
            if out.channel != "discord":
                await q.put(out)
                await asyncio.sleep(0.01)
                continue
            ch = client.get_channel(int(out.chat_id))
            if ch:
                try:
                    await ch.send(out.text or "\u200b")
                except Exception as e:
                    print(f"[discord] send error: {e}")

    asyncio.ensure_future(client.start(dc.bot_token))
    ::py::
}
