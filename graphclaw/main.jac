# graphclaw/main.jac
# Entry point -- starts all channels and the agent dispatch loop.

import from graphclaw.config.loader { load_config, ensure_workspace }
import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage }
import from graphclaw.channels.telegram { start_telegram_channel }
import from graphclaw.channels.discord { start_discord_channel }
import from graphclaw.channels.slack { start_slack_channel }
import from graphclaw.channels.email { start_email_channel }
import from graphclaw.channels.whatsapp { start_whatsapp_channel }
import from graphclaw.memory.dream { Dream }


def dispatch_message(msg: InboundMessage) {
    ::py::
    import asyncio
    import traceback

    from graphclaw.agents.coordinator_runtime import run_coordinator
    from graphclaw.memory.backend import append_turn, consolidate_session, get_memory_context, start_session

    def _extract_content(result: object) -> str:
        if result is None:
            return "[No response]"
        if hasattr(result, "content"):
            return result.content or "[No response]"
        if isinstance(result, dict):
            return result.get("content", str(result))
        return str(result)

    async def _handle():
        session_id = ""
        try:
            session_id = start_session(
                channel=msg.channel,
                chat_id=msg.chat_id,
                user_id=msg.user_id,
                agent="coordinator",
            )
            append_turn(session_id=session_id, role="user", content=msg.text)

            memory_context = get_memory_context(max_chars=3000)
            query = msg.text
            if memory_context:
                query = f"Memory context:\n{memory_context}\n\nUser message:\n{msg.text}"

            result = await run_coordinator(
                query=query,
                channel=msg.channel,
                chat_id=msg.chat_id,
                user_id=msg.user_id,
            )
            content = _extract_content(result)

            append_turn(session_id=session_id, role="assistant", content=content)
            consolidate_session(session_id)
            bus.publish_outbound(OutboundMessage(channel=msg.channel, chat_id=msg.chat_id, text=content))
        except Exception as e:
            if session_id:
                append_turn(session_id=session_id, role="assistant", content=f"[Error] {e}")
            bus.publish_outbound(OutboundMessage(channel=msg.channel, chat_id=msg.chat_id, text=f"[Error] {str(e)}"))
            traceback.print_exc()

    asyncio.ensure_future(_handle())
    ::py::
}


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


with entry {
    ::py::
    import asyncio
    import sys

    from graphclaw.update_manager import maybe_prompt_for_update

    cfg = load_config()
    ensure_workspace()
    print(f"[graphclaw] starting -- workspace: {cfg.workspace}")

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

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(_start_channels())

    if channels_started:
        print("[graphclaw] channels: " + ", ".join(channels_started))
    else:
        print("[graphclaw] no channels enabled -- running in CLI mode")
        update_prompt = maybe_prompt_for_update()
        if update_prompt.action == "updated":
            print(f"[graphclaw] {update_prompt.message}")
            sys.exit(0)
        if update_prompt.action == "error":
            print(f"[graphclaw] Update check failed: {update_prompt.message}")

    start_dispatch_loop()
    start_dream_scheduler()

    print("[graphclaw] ready")

    if not channels_started:
        async def cli_loop():
            print("Type your message (Ctrl+C to exit):")
            while True:
                try:
                    text = await loop.run_in_executor(None, input, "> ")
                    if text.strip():
                        bus.publish_inbound(InboundMessage(channel="cli", chat_id="local", user_id="user", text=text.strip()))
                        q = bus.get_outbound_queue("cli")
                        out = await q.get()
                        print(f"\n{out.text}\n")
                except (EOFError, KeyboardInterrupt):
                    print("\n[graphclaw] bye")
                    loop.stop()
                    return

        asyncio.ensure_future(cli_loop())

    try:
        loop.run_forever()
    except KeyboardInterrupt:
        print("\n[graphclaw] shutting down")
    ::py::
}
