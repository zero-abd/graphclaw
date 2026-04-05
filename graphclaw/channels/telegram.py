"""Telegram channel integration using python-telegram-bot."""
from __future__ import annotations
import asyncio
import sys
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.config.loader import load_config


async def start_telegram_channel() -> bool:
    """Start the Telegram bot in the background."""
    cfg = load_config()
    ch = cfg.channels.get("telegram", {})
    token = ch.get("bot_token", "")
    if not token:
        print("[telegram] no bot_token configured, skipping")
        return False

    allowed_ids = set(str(x) for x in ch.get("allowed_ids", []))

    try:
        from telegram import Update
        from telegram.ext import ApplicationBuilder, MessageHandler, filters, ContextTypes
    except ImportError:
        print(f"[telegram] python-telegram-bot not installed — install it with: {sys.executable} -m pip install 'python-telegram-bot>=21.0'")
        return False

    app = ApplicationBuilder().token(token).build()

    async def on_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        if not update.message or not update.message.text:
            return False
        uid = str(update.effective_user.id) if update.effective_user else "unknown"
        cid = str(update.effective_chat.id) if update.effective_chat else "unknown"

        if allowed_ids and uid not in allowed_ids:
            return False

        bus.publish_inbound(InboundMessage(
            channel="telegram",
            chat_id=cid,
            user_id=uid,
            text=update.message.text,
        ))

    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_message))

    # Outbound send loop
    async def _send_loop() -> None:
        q = bus.get_outbound_queue("telegram")
        while True:
            msg: OutboundMessage = await q.get()
            try:
                await app.bot.send_message(chat_id=msg.chat_id, text=msg.text)
            except Exception as e:
                print(f"[telegram] send error: {e}")

    asyncio.ensure_future(_send_loop())

    # Start polling
    print("[telegram] starting polling")
    await app.initialize()
    await app.start()
    await app.updater.start_polling(drop_pending_updates=True)
    return True
