# graphclaw/main.jac
# Entry point -- starts all channels and the agent dispatch loop
# Memory layer is Jac (graph-native), everything else is Python

import from graphclaw.config.loader { load_config, ensure_workspace }
import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage }
import from graphclaw.channels.telegram { start_telegram_channel }
import from graphclaw.channels.discord { start_discord_channel }
import from graphclaw.channels.slack { start_slack_channel }
import from graphclaw.channels.email { start_email_channel }
import from graphclaw.channels.whatsapp { start_whatsapp_channel }
import from graphclaw.memory.store { StartSession, AppendTurn }
import from graphclaw.memory.recall { GetMemoryContext }
import from graphclaw.memory.dream { Dream }
import from graphclaw.memory.consolidate { ConsolidateAll }

# -- Agent dispatch ----------------------------------------------------------------

def dispatch_message(msg: InboundMessage) {
    ::py::
    import asyncio, traceback
    from graphclaw.agents.coordinator import CoordinatorAgent

    async def _handle():
        try:
            # Spawn coordinator walker on root to get intent routing + graph access
            result = CoordinatorAgent(
                query=msg.text,
                channel=msg.channel,
                chat_id=msg.chat_id,
                user_id=msg.user_id
            ).spawn(root())

            content = "[No response]"
            if result:
                if hasattr(result, 'content'):
                    content = result.content
                elif isinstance(result, dict):
                    content = result.get('content', str(result))
                else:
                    content = str(result)

            bus.publish_outbound(OutboundMessage(
                channel=msg.channel,
                chat_id=msg.chat_id,
                text=content
            ))
        except Exception as e:
            bus.publish_outbound(OutboundMessage(
                channel=msg.channel,
                chat_id=msg.chat_id,
                text=f"[Error] {str(e)}"
            ))
            traceback.print_exc()

    asyncio.ensure_future(_handle())
    ::py::
}

# -- Inbound message consumer ------------------------------------------------------

def start_dispatch_loop() {
    ::py::
    import asyncio

    async def _loop():
        q = bus.get_inbound_queue()
        while True:
            msg = await q.get()
            try:
                dispatch_message(msg)
            except Exception as e:
                print(f"[dispatch] error: {e}")

    asyncio.ensure_future(_loop())
    ::py::
}

# -- Dream scheduler ---------------------------------------------------------------

def start_dream_scheduler() {
    ::py::
    import asyncio

    async def _dream_loop():
        cfg = load_config()
        interval_s = cfg.agents.dream.interval_hours * 3600
        while True:
            await asyncio.sleep(interval_s)
            try:
                Dream().spawn(root())
                print("[dream] memory maintenance completed")
            except Exception as e:
                print(f"[dream] error: {e}")

    if load_config().agents.dream.enabled:
        asyncio.ensure_future(_dream_loop())
    ::py::
}

# -- Main entry --------------------------------------------------------------------

with entry {
    ::py::
    import asyncio, sys

    cfg = load_config()
    ensure_workspace()
    print(f"[graphclaw] starting -- workspace: {cfg.workspace}")

    # Start channels
    channels_started = []

    async def _start_channels():
        ch = cfg.channels
        if ch.get("telegram", {}).get("enabled"):
            await start_telegram_channel()
            channels_started.append("telegram")
        if ch.get("discord", {}).get("enabled"):
            await start_discord_channel()
            channels_started.append("discord")
        if ch.get("slack", {}).get("enabled"):
            await start_slack_channel()
            channels_started.append("slack")
        if ch.get("email", {}).get("enabled"):
            await start_email_channel()
            channels_started.append("email")
        if ch.get("whatsapp", {}).get("enabled"):
            await start_whatsapp_channel()
            channels_started.append("whatsapp")

    loop = asyncio.get_event_loop()
    loop.run_until_complete(_start_channels())

    if channels_started:
        print(f"[graphclaw] channels: {', '.join(channels_started)}")
    else:
        print("[graphclaw] no channels enabled -- running in CLI mode")

    # Start dispatch loop and dream scheduler
    start_dispatch_loop()
    start_dream_scheduler()

    print("[graphclaw] ready")

    # CLI mode: read from stdin if no channels
    if not channels_started:
        async def cli_loop():
            print("Type your message (Ctrl+C to exit):")
            while True:
                try:
                    text = await loop.run_in_executor(None, input, "> ")
                    if text.strip():
                        bus.publish_inbound(InboundMessage(
                            channel="cli",
                            chat_id="local",
                            user_id="user",
                            text=text.strip()
                        ))
                        # Wait for response
                        await asyncio.sleep(0.5)
                        q = bus.get_outbound_queue()
                        while not q.empty():
                            out = await q.get()
                            print(f"\n{out.text}\n")
                except (EOFError, KeyboardInterrupt):
                    print("\n[graphclaw] bye")
                    sys.exit(0)
        asyncio.ensure_future(cli_loop())

    try:
        loop.run_forever()
    except KeyboardInterrupt:
        print("\n[graphclaw] shutting down")
    ::py::
}
