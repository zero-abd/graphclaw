"""Email channel integration using IMAP/SMTP."""
from __future__ import annotations
import asyncio
from graphclaw.channels.bus import bus, InboundMessage, OutboundMessage
from graphclaw.config.loader import load_config


async def start_email_channel() -> None:
    """Start the email channel in the background."""
    cfg = load_config()
    ch = cfg.channels.get("email", {})
    if not ch.get("enabled"):
        return

    imap_host = ch.get("imap_host", "")
    smtp_host = ch.get("smtp_host", "")
    username = ch.get("username", "")
    password = ch.get("password", "")
    poll_interval = ch.get("poll_interval", 30)

    if not all([imap_host, username, password]):
        print("[email] incomplete config, skipping")
        return

    async def _poll_loop() -> None:
        import imaplib
        import email as email_lib

        while True:
            try:
                mail = imaplib.IMAP4_SSL(imap_host)
                mail.login(username, password)
                mail.select("inbox")
                _, msg_ids = mail.search(None, "UNSEEN")

                for mid in msg_ids[0].split():
                    if not mid:
                        continue
                    _, data = mail.fetch(mid, "(RFC822)")
                    raw = data[0][1]
                    msg = email_lib.message_from_bytes(raw)
                    sender = msg.get("From", "unknown")
                    subject = msg.get("Subject", "")
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body = part.get_payload(decode=True).decode("utf-8", errors="replace")
                                break
                    else:
                        body = msg.get_payload(decode=True).decode("utf-8", errors="replace")

                    bus.publish_inbound(InboundMessage(
                        channel="email",
                        chat_id=sender,
                        user_id=sender,
                        text=f"Subject: {subject}\n\n{body}".strip(),
                    ))

                mail.logout()
            except Exception as e:
                print(f"[email] poll error: {e}")

            await asyncio.sleep(poll_interval)

    async def _send_loop() -> None:
        import smtplib
        from email.mime.text import MIMEText

        q = bus.get_outbound_queue()
        while True:
            msg: OutboundMessage = await q.get()
            if msg.channel != "email":
                q.put_nowait(msg)
                await asyncio.sleep(0.05)
                continue
            try:
                mime = MIMEText(msg.text)
                mime["From"] = username
                mime["To"] = msg.chat_id
                mime["Subject"] = msg.metadata.get("subject", "Graphclaw")
                with smtplib.SMTP_SSL(smtp_host) as server:
                    server.login(username, password)
                    server.send_message(mime)
            except Exception as e:
                print(f"[email] send error: {e}")

    asyncio.ensure_future(_poll_loop())
    asyncio.ensure_future(_send_loop())
    print("[email] started")
