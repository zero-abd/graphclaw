# graphclaw/main.jac
# Entry point — starts all channels and the agent dispatch loop

import from graphclaw.config.loader { load_config, ensure_workspace };
import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage };
import from graphclaw.channels.telegram { start_telegram_channel };
import from graphclaw.channels.discord { start_discord_channel };
import from graphclaw.channels.slack { start_slack_channel };
import from graphclaw.channels.email { start_email_channel };
import from graphclaw.channels.whatsapp { start_whatsapp_channel };
import from graphclaw.agents.coordinator { CoordinatorAgent };
import from graphclaw.memory.dream { Dream };
import from graphclaw.skills.loader { LoadSkills };
import from asyncio { get_event_loop, Lock };

# ── Per-session concurrency gate ───────────────────────────────────────────────

glob _session_locks: dict = {};
glob _global_sem: any = None;

def _get_session_lock(key: str) -> any {
    global _session_locks;
    ::py::
    import asyncio
    if key not in _session_locks:
        _session_locks[key] = asyncio.Lock()
    _result = _session_locks[key]
    ::py::
    return _result;
}

# ── Agent dispatch ─────────────────────────────────────────────────────────────

walker DispatchMessage {
    has msg: InboundMessage;

    can dispatch with `root entry {
        cfg = load_config();
        session_key = f"{self.msg.channel}:{self.msg.chat_id}";

        ::py::
        import asyncio, traceback

        lock = _get_session_lock(session_key)

        async def _run():
            async with lock:
                try:
                    result = CoordinatorAgent(
                        query=self.msg.text,
                        channel=self.msg.channel,
                        chat_id=self.msg.chat_id,
                        user_id=self.msg.user_id
                    ).spawn(here)   # here = root

                    out = OutboundMessage(
                        channel=self.msg.channel,
                        chat_id=self.msg.chat_id,
                        text=result.content if result else "[No response]"
                    )
                    bus.publish_outbound(out)
                except Exception as e:
                    err_msg = OutboundMessage(
                        channel=self.msg.channel,
                        chat_id=self.msg.chat_id,
                        text=f"[Error] {str(e)}"
                    )
                    bus.publish_outbound(err_msg)
                    traceback.print_exc()

        asyncio.ensure_future(_run())
        ::py::
    }
}

# ── Inbound message consumer ───────────────────────────────────────────────────

def start_dispatch_loop() {
    ::py::
    import asyncio

    async def _loop():
        q = bus.get_inbound_queue()
        while True:
            msg = await q.get()
            # Spawn dispatch walker for each inbound message
            # In a real jac runtime, this would use spawn on root
            # Here we call directly for simplicity
            try:
                DispatchMessage(msg=msg).spawn(root)
            except Exception as e:
                print(f"[dispatch] error: {e}")

    asyncio.ensure_future(_loop())
    ::py::
}

# ── Dream scheduler ────────────────────────────────────────────────────────────

def start_dream_scheduler() {
    ::py::
    import asyncio

    async def _dream_loop():
        cfg = load_config()
        interval_s = cfg.agents.dream.interval_hours * 3600
        while True:
            await asyncio.sleep(interval_s)
            try:
                Dream().spawn(root)
                print("[dream] completed")
            except Exception as e:
                print(f"[dream] error: {e}")

    if load_config().agents.dream.enabled:
        asyncio.ensure_future(_dream_loop())
    ::py::
}

# ── Main entry ────────────────────────────────────────────────────────────────

with entry {
    ::py::
    import asyncio, sys

    cfg = load_config()
    ensure_workspace()
    print(f"[graphclaw] starting — workspace: {cfg.workspace}")

    # Load skills into graph
    LoadSkills().spawn(root)
    print("[graphclaw] skills loaded")

    # Start channels
    channels_started = []
    if cfg.channels.telegram.enabled:
        start_telegram_channel()
        channels_started.append("telegram")
    if cfg.channels.discord.enabled:
        start_discord_channel()
        channels_started.append("discord")
    if cfg.channels.slack.enabled:
        start_slack_channel()
        channels_started.append("slack")
    if cfg.channels.email.enabled:
        start_email_channel()
        channels_started.append("email")
    if cfg.channels.whatsapp.enabled:
        start_whatsapp_channel()
        channels_started.append("whatsapp")

    if channels_started:
        print(f"[graphclaw] channels: {', '.join(channels_started)}")
    else:
        print("[graphclaw] no channels enabled — running in CLI mode")

    # Start dispatch loop and dream scheduler
    start_dispatch_loop()
    start_dream_scheduler()

    print("[graphclaw] ready")

    # CLI mode: read from stdin if no channels
    if not channels_started:
        async def cli_loop():
            from graphclaw.channels.bus import InboundMessage, OutboundMessage
            print("Type your message (Ctrl+C to exit):")
            while True:
                try:
                    text = await asyncio.get_event_loop().run_in_executor(
                        None, input, "> "
                    )
                    if text.strip():
                        bus.publish_inbound(InboundMessage(
                            channel="cli",
                            chat_id="local",
                            user_id="user",
                            text=text.strip()
                        ))
                        # Wait briefly for response
                        await asyncio.sleep(0.1)
                        q = bus.get_outbound_queue()
                        while not q.empty():
                            out = await q.get()
                            print(f"\n[assistant] {out.text}\n")
                except (EOFError, KeyboardInterrupt):
                    print("\n[graphclaw] bye")
                    sys.exit(0)
        asyncio.ensure_future(cli_loop())

    try:
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        print("\n[graphclaw] shutting down")
    ::py::
}
