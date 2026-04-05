# graphclaw/channels/telegram.jac

import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage };
import from graphclaw.config.loader { load_config };

def start_telegram_channel() {
    ::py::
    import asyncio
    from telegram import Update
    from telegram.ext import Application, MessageHandler, filters, ContextTypes
    from telegram.constants import ParseMode, ChatAction

    cfg = load_config()
    tc = cfg.channels.telegram
    if not tc.enabled or not tc.bot_token:
        return

    async def handle_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
        msg = update.message
        if not msg or not msg.text:
            return
        user_id = str(msg.from_user.id) if msg.from_user else ""

        # Check allowed users
        if tc.allowed_user_ids and int(user_id) not in tc.allowed_user_ids:
            await msg.reply_text("Unauthorized.")
            return

        await context.bot.send_chat_action(chat_id=msg.chat_id, action=ChatAction.TYPING)

        inbound = InboundMessage(
            channel="telegram",
            chat_id=str(msg.chat_id),
            user_id=user_id,
            text=msg.text,
            raw=msg.to_dict()
        )
        bus.publish_inbound(inbound)

    async def send_loop(app):
        q = bus.get_outbound_queue()
        while True:
            out: OutboundMessage = await q.get()
            if out.channel != "telegram":
                await q.put(out)   # put back for other handlers
                await asyncio.sleep(0.01)
                continue
            parse = ParseMode.MARKDOWN if out.parse_mode == "markdown" else None
            try:
                await app.bot.send_message(
                    chat_id=out.chat_id,
                    text=out.text or "\u200b",
                    parse_mode=parse
                )
            except Exception as e:
                print(f"[telegram] send error: {e}")

    app = Application.builder().token(tc.bot_token).build()
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_message))

    async def run():
        async with app:
            await app.start()
            asyncio.create_task(send_loop(app))
            await app.updater.start_polling(drop_pending_updates=True)
            await asyncio.Event().wait()   # run forever

    asyncio.ensure_future(run())
    ::py::
}
