# graphclaw/channels/whatsapp.jac
# Uses the Node.js Baileys bridge (from nanobot/bridge/)
# Bridge must be running separately: cd bridge && npm start

import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage }
import from graphclaw.config.loader { load_config }

def start_whatsapp_channel() {
    ::py::
    import asyncio, aiohttp, json

    cfg = load_config()
    wc = cfg.channels.whatsapp
    if not wc.enabled or not wc.bridge_url:
        return

    bridge_url = wc.bridge_url.rstrip("/")
    auth_token = wc.auth_token

    def _headers():
        h = {"Content-Type": "application/json"}
        if auth_token:
            h["Authorization"] = f"Bearer {auth_token}"
        return h

    async def poll_bridge():
        """Poll the bridge HTTP endpoint for new messages."""
        last_ts = 0
        async with aiohttp.ClientSession() as session:
            while True:
                try:
                    async with session.get(
                        f"{bridge_url}/messages?since={last_ts}",
                        headers=_headers(), timeout=aiohttp.ClientTimeout(total=10)
                    ) as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            for msg in data.get("messages", []):
                                last_ts = max(last_ts, msg.get("ts", 0))
                                inbound = InboundMessage(
                                    channel="whatsapp",
                                    chat_id=msg.get("from", ""),
                                    user_id=msg.get("from", ""),
                                    text=msg.get("body", ""),
                                    raw=msg
                                )
                                bus.publish_inbound(inbound)
                except Exception as e:
                    print(f"[whatsapp] poll error: {e}")
                await asyncio.sleep(2)

    async def send_loop():
        q = bus.get_outbound_queue()
        async with aiohttp.ClientSession() as session:
            while True:
                out: OutboundMessage = await q.get()
                if out.channel != "whatsapp":
                    await q.put(out)
                    await asyncio.sleep(0.01)
                    continue
                try:
                    async with session.post(
                        f"{bridge_url}/send",
                        headers=_headers(),
                        json={"to": out.chat_id, "body": out.text or ""},
                        timeout=aiohttp.ClientTimeout(total=10)
                    ) as resp:
                        if resp.status not in (200, 201):
                            print(f"[whatsapp] send failed: {await resp.text()}")
                except Exception as e:
                    print(f"[whatsapp] send error: {e}")

    asyncio.ensure_future(poll_bridge())
    asyncio.ensure_future(send_loop())
    ::py::
}
