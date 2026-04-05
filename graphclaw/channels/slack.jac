# graphclaw/channels/slack.jac

import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage };
import from graphclaw.config.loader { load_config };

def start_slack_channel() {
    ::py::
    import asyncio
    from slack_bolt.async_app import AsyncApp
    from slack_bolt.adapter.socket_mode.async_handler import AsyncSocketModeHandler

    cfg = load_config()
    sc = cfg.channels.slack
    if not sc.enabled or not sc.bot_token:
        return

    app = AsyncApp(token=sc.bot_token, signing_secret=sc.signing_secret)

    @app.event("message")
    async def handle_message(body, say):
        event = body.get("event", {})
        if event.get("bot_id"):   # ignore bot messages
            return
        text = event.get("text", "")
        channel_id = event.get("channel", "")
        user_id = event.get("user", "")

        inbound = InboundMessage(
            channel="slack",
            chat_id=channel_id,
            user_id=user_id,
            text=text,
            raw=event
        )
        bus.publish_inbound(inbound)

    async def send_loop():
        q = bus.get_outbound_queue()
        while True:
            out: OutboundMessage = await q.get()
            if out.channel != "slack":
                await q.put(out)
                await asyncio.sleep(0.01)
                continue
            try:
                await app.client.chat_postMessage(
                    channel=out.chat_id,
                    text=out.text or "\u200b",
                    mrkdwn=(out.parse_mode == "markdown")
                )
            except Exception as e:
                print(f"[slack] send error: {e}")

    async def run():
        asyncio.create_task(send_loop())
        handler = AsyncSocketModeHandler(app, sc.app_token)
        await handler.start_async()

    asyncio.ensure_future(run())
    ::py::
}
