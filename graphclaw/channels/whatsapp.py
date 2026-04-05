"""WhatsApp channel integration via Baileys bridge."""
from __future__ import annotations
import asyncio
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.config.loader import load_config


async def start_whatsapp_channel() -> None:
    """Start the WhatsApp channel in the background."""
    cfg = load_config()
    ch = cfg.channels.get("whatsapp", {})
    if not ch.get("enabled"):
        return

    bridge_url = ch.get("bridge_url", "http://localhost:3001")
    api_token = ch.get("api_token", "")
    poll_interval = ch.get("poll_interval", 2)

    if not bridge_url:
        print("[whatsapp] no bridge_url configured, skipping")
        return

    async def _poll_loop() -> None:
        try:
            import aiohttp
        except ImportError:
            print("[whatsapp] aiohttp not installed — pip install aiohttp")
            return

        headers = {}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        async with aiohttp.ClientSession() as session:
            while True:
                try:
                    async with session.get(
                        f"{bridge_url}/messages", headers=headers, timeout=aiohttp.ClientTimeout(total=10)
                    ) as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            for msg in data.get("messages", []):
                                bus.publish_inbound(InboundMessage(
                                    channel="whatsapp",
                                    chat_id=msg.get("chat_id", ""),
                                    user_id=msg.get("sender", ""),
                                    text=msg.get("text", ""),
                                ))
                except Exception as e:
                    print(f"[whatsapp] poll error: {e}")

                await asyncio.sleep(poll_interval)

    async def _send_loop() -> None:
        try:
            import aiohttp
        except ImportError:
            return

        headers = {"Content-Type": "application/json"}
        if api_token:
            headers["Authorization"] = f"Bearer {api_token}"

        async with aiohttp.ClientSession() as session:
            q = bus.get_outbound_queue("whatsapp")
            while True:
                msg: OutboundMessage = await q.get()
                try:
                    import json
                    await session.post(
                        f"{bridge_url}/send",
                        headers=headers,
                        data=json.dumps({"chat_id": msg.chat_id, "text": msg.text}),
                    )
                except Exception as e:
                    print(f"[whatsapp] send error: {e}")

    asyncio.ensure_future(_poll_loop())
    asyncio.ensure_future(_send_loop())
    print("[whatsapp] started")
