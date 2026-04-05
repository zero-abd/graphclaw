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
    from graphclaw.channels.auth import approve_pairing_request, list_pending_requests
    from graphclaw.memory.backend import (
        append_turn,
        consolidate_session,
        extract_assistant_name_change,
        get_assistant_name,
        get_memory_context,
        start_session,
    )
    from graphclaw.skills.approval import maybe_handle_skill_install_reply

    def _extract_content(result: object) -> str:
        if result is None:
            return "[No response]"
        if hasattr(result, "content"):
            return result.content or "[No response]"
        if isinstance(result, dict):
            return result.get("content", str(result))
        return str(result)

    def _maybe_handle_local_pairing_command(raw_text: str) -> str | None:
        normalized = raw_text.strip().lstrip('/')
        parts = normalized.split()
        if len(parts) < 3 or parts[0].lower() != "pairing":
            return None
        action = parts[1].lower()
        channel = parts[2].lower()
        if action == "list":
            return list_pending_requests(channel)
        if action == "approve" and len(parts) >= 4:
            decision = approve_pairing_request(channel, parts[3])
            for notification in decision.notifications:
                bus.publish_outbound(OutboundMessage(channel=channel, chat_id=notification.chat_id, text=notification.text))
            if decision.responses:
                return "\n".join(decision.responses)
            return f"Processed pairing approval for {channel}."
        return "Usage: pairing list <channel> | pairing approve <channel> <code>"

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

            local_pairing_response = None
            if msg.channel == "cli":
                local_pairing_response = _maybe_handle_local_pairing_command(msg.text)
            if local_pairing_response is not None:
                append_turn(session_id=session_id, role="assistant", content=local_pairing_response)
                consolidate_session(session_id)
                bus.publish_outbound(OutboundMessage(channel=msg.channel, chat_id=msg.chat_id, text=local_pairing_response))
                return

            assistant_name = get_assistant_name()
            skill_install_reply = await maybe_handle_skill_install_reply(
                msg.text,
                channel=msg.channel,
                chat_id=msg.chat_id,
                user_id=msg.user_id,
            )
            if skill_install_reply is not None and skill_install_reply.get("handled"):
                resumed_content = ""
                if skill_install_reply.get("resume_query"):
                    resumed_result = await run_coordinator(
                        query=skill_install_reply["resume_query"],
                        channel=msg.channel,
                        chat_id=msg.chat_id,
                        user_id=msg.user_id,
                        assistant_name=assistant_name,
                    )
                    resumed_content = _extract_content(resumed_result)

                content = str(skill_install_reply.get("message", "") or "").strip()
                if resumed_content:
                    content = f"{content}\n\n{resumed_content}" if content else resumed_content

                append_turn(session_id=session_id, role="assistant", content=content)
                consolidate_session(session_id)
                bus.publish_outbound(OutboundMessage(channel=msg.channel, chat_id=msg.chat_id, text=content))
                return

            renamed_to = extract_assistant_name_change(msg.text)
            if renamed_to:
                content = f"Got it — I'll go by {renamed_to} from now on."
                append_turn(session_id=session_id, role="assistant", content=content)
                consolidate_session(session_id)
                bus.publish_outbound(OutboundMessage(channel=msg.channel, chat_id=msg.chat_id, text=content))
                return

            memory_context = get_memory_context(max_chars=3000)
            query = msg.text
            if memory_context:
                query = f"Memory context:\n{memory_context}\n\nUser message:\n{msg.text}"

            result = await run_coordinator(
                query=query,
                channel=msg.channel,
                chat_id=msg.chat_id,
                user_id=msg.user_id,
                assistant_name=assistant_name,
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

    from graphclaw.dashboard_runtime import ensure_local_dashboard
    from graphclaw.setup_runtime import maybe_prompt_for_provider_key
    from graphclaw.update_manager import maybe_prompt_for_update

    cfg = load_config()
    ensure_workspace()
    print(f"[graphclaw] starting -- workspace: {cfg.workspace}")

    dashboard_url = None
    if sys.stdin and sys.stdin.isatty():
        try:
            dashboard_url = ensure_local_dashboard(open_browser=True)
            if dashboard_url:
                print(f"[graphclaw] dashboard: {dashboard_url}")
        except Exception as exc:
            print(f"[graphclaw] dashboard startup warning: {exc}")

    channels_started = []
    channel_failures = []

    async def _try_start_channel(name, starter):
        try:
            started = await starter()
        except Exception as exc:
            print(f"[{name}] startup error: {exc}")
            channel_failures.append(name)
            return
        if started:
            channels_started.append(name)
        else:
            channel_failures.append(name)

    async def _start_channels():
        ch = cfg.channels
        if ch.get("telegram", {}).get("enabled"):
            await _try_start_channel("telegram", start_telegram_channel)
        if ch.get("discord", {}).get("enabled"):
            await _try_start_channel("discord", start_discord_channel)
        if ch.get("slack", {}).get("enabled"):
            await _try_start_channel("slack", start_slack_channel)
        if ch.get("email", {}).get("enabled"):
            await _try_start_channel("email", start_email_channel)
        if ch.get("whatsapp", {}).get("enabled"):
            await _try_start_channel("whatsapp", start_whatsapp_channel)

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(_start_channels())

    if channels_started:
        print("[graphclaw] channels: " + ", ".join(channels_started))
    elif channel_failures:
        print("[graphclaw] enabled channels failed to start: " + ", ".join(channel_failures))
        print("[graphclaw] falling back to local CLI mode")
    else:
        print("[graphclaw] no channels enabled -- running in CLI mode")

    if channel_failures:
        print("[graphclaw] fix the channel setup above, or disable that channel in config.json to suppress the warning")
        key_prompt = maybe_prompt_for_provider_key()
        if key_prompt.action == "saved":
            print(f"[graphclaw] {key_prompt.message}")
        update_prompt = maybe_prompt_for_update()
        if update_prompt.action == "updated":
            print(f"[graphclaw] {update_prompt.message}")
            sys.exit(0)
        if update_prompt.action == "error":
            print(f"[graphclaw] Update check failed: {update_prompt.message}")

    start_dispatch_loop()
    start_dream_scheduler()

    print("[graphclaw] ready")

    interactive_cli_enabled = bool(sys.stdin and sys.stdin.isatty())
    if interactive_cli_enabled:
        async def cli_loop():
            if channels_started:
                print("[graphclaw] local CLI enabled — use it for chat or pairing commands (Ctrl+C to exit):")
            else:
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
