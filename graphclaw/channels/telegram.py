"""Telegram channel integration using python-telegram-bot."""
from __future__ import annotations
import asyncio
import logging
import mimetypes
import sys
from pathlib import Path
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.channels.auth import AuthEvent, ChannelAuthManager
from graphclaw.config.loader import load_config


def _configure_telegram_logging() -> None:
    for logger_name in ("httpx", "httpcore", "telegram", "telegram.ext"):
        logging.getLogger(logger_name).setLevel(logging.WARNING)


def _print_onboarding(bot_username: str, auth: ChannelAuthManager) -> None:
    if not bot_username:
        return
    bot_handle = f"@{bot_username}"
    bot_url = f"https://t.me/{bot_username}"
    print(f"[telegram] bot ready: {bot_handle}")
    print(f"[telegram] first-use: open {bot_url}")
    print("[telegram] first-use: press Start in Telegram, then send any message to begin the DM")
    if auth.dm_policy == "pairing":
        print("[telegram] first-use: if you receive a pairing code, approve it here in this terminal with:")
        print("[telegram]            pairing list telegram")
        print("[telegram]            pairing approve telegram <code>")


async def start_telegram_channel() -> bool:
    """Start the Telegram bot in the background."""
    cfg = load_config()
    ch = cfg.channels.get("telegram", {})
    token = ch.get("bot_token", "")
    if not token:
        print("[telegram] no bot_token configured, skipping")
        return False

    try:
        from telegram import Update
        from telegram.ext import ApplicationBuilder, MessageHandler, filters, ContextTypes
    except ImportError:
        print(f"[telegram] python-telegram-bot not installed — install it with: {sys.executable} -m pip install 'python-telegram-bot>=21.0'")
        return False

    _configure_telegram_logging()
    app = ApplicationBuilder().token(token).build()
    auth = ChannelAuthManager("telegram", ch)

    for warning in auth.startup_warnings():
        print(f"[telegram] {warning}")

    await app.initialize()
    me = await app.bot.get_me()
    bot_id = str(me.id)
    bot_username = (me.username or "").lstrip("@").lower()
    _print_onboarding(bot_username, auth)

    async def _send_auth_message(chat_id: str, text: str) -> None:
        try:
            await app.bot.send_message(chat_id=chat_id, text=text)
        except Exception as exc:
            print(f"[telegram] auth reply error: {exc}")

    async def on_message(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        if not update.message or not update.message.text:
            return None
        uid = str(update.effective_user.id) if update.effective_user else "unknown"
        cid = str(update.effective_chat.id) if update.effective_chat else "unknown"
        chat = update.effective_chat
        user = update.effective_user
        is_direct = bool(chat and chat.type == "private")
        reply_to_bot = bool(
            update.message.reply_to_message
            and update.message.reply_to_message.from_user
            and str(update.message.reply_to_message.from_user.id) == bot_id
        )
        entities = update.message.entities or []
        is_mentioned = reply_to_bot
        for entity in entities:
            if entity.type != "mention":
                continue
            mention = update.message.text[entity.offset : entity.offset + entity.length].lstrip("@").lower()
            if bot_username and mention == bot_username:
                is_mentioned = True
                break

        decision = auth.evaluate(
            AuthEvent(
                channel="telegram",
                user_id=uid,
                chat_id=cid,
                text=update.message.text,
                is_direct=is_direct,
                username=(user.username or "") if user else "",
                display_name=(user.full_name or "") if user else "",
                is_mentioned=is_mentioned,
                mention_detection_available=bool(bot_username or bot_id),
                channel_name=(chat.title or "") if chat else "",
                group_id=cid,
            )
        )

        for response in decision.responses:
            await _send_auth_message(cid, response)
        for notification in decision.notifications:
            await _send_auth_message(notification.chat_id, notification.text)
        if not decision.allow_publish:
            return None

        bus.publish_inbound(InboundMessage(
            channel="telegram",
            chat_id=cid,
            user_id=uid,
            text=update.message.text,
            metadata=decision.metadata,
        ))

    app.add_handler(MessageHandler(filters.TEXT, on_message))

    # Outbound send loop
    async def _send_loop() -> None:
        q = bus.get_outbound_queue("telegram")
        while True:
            msg: OutboundMessage = await q.get()
            try:
                caption_sent = False
                if msg.text:
                    await app.bot.send_message(chat_id=msg.chat_id, text=msg.text)
                    caption_sent = True
                for media_path in msg.media or []:
                    path = Path(media_path)
                    if not path.exists():
                        continue
                    mime, _ = mimetypes.guess_type(str(path))
                    with path.open("rb") as handle:
                        if mime and mime.startswith("image/"):
                            await app.bot.send_photo(
                                chat_id=msg.chat_id,
                                photo=handle,
                                caption=None if caption_sent else msg.text,
                            )
                        else:
                            await app.bot.send_document(
                                chat_id=msg.chat_id,
                                document=handle,
                                caption=None if caption_sent else msg.text,
                            )
                    caption_sent = True
            except Exception as e:
                print(f"[telegram] send error: {e}")

    asyncio.ensure_future(_send_loop())

    # Start polling
    print("[telegram] starting polling")
    await app.start()
    await app.updater.start_polling(drop_pending_updates=True)
    return True
