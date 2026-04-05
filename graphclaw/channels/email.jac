# graphclaw/channels/email.jac

import from graphclaw.channels.bus { bus, InboundMessage, OutboundMessage }
import from graphclaw.config.loader { load_config }

def start_email_channel() {
    ::py::
    import asyncio, imaplib, email as email_lib, aiosmtplib
    from email.message import EmailMessage

    cfg = load_config()
    ec = cfg.channels.email
    if not ec.enabled or not ec.username:
        return

    seen_ids = set()

    async def poll_inbox():
        while True:
            try:
                mail = imaplib.IMAP4_SSL(ec.imap_host, ec.imap_port)
                mail.login(ec.username, ec.password)
                mail.select("inbox")
                _, data = mail.search(None, "UNSEEN")
                for num in data[0].split():
                    if num in seen_ids:
                        continue
                    seen_ids.add(num)
                    _, msg_data = mail.fetch(num, "(RFC822)")
                    msg = email_lib.message_from_bytes(msg_data[0][1])
                    sender = msg.get("From", "")
                    subject = msg.get("Subject", "")
                    body = ""
                    if msg.is_multipart():
                        for part in msg.walk():
                            if part.get_content_type() == "text/plain":
                                body = part.get_payload(decode=True).decode("utf-8", errors="replace")
                                break
                    else:
                        body = msg.get_payload(decode=True).decode("utf-8", errors="replace")

                    inbound = InboundMessage(
                        channel="email",
                        chat_id=sender,
                        user_id=sender,
                        text=f"Subject: {subject}\n\n{body}",
                        raw={"subject": subject, "from": sender}
                    )
                    bus.publish_inbound(inbound)
                mail.logout()
            except Exception as e:
                print(f"[email] poll error: {e}")
            await asyncio.sleep(ec.poll_interval_s)

    async def send_loop():
        q = bus.get_outbound_queue()
        while True:
            out: OutboundMessage = await q.get()
            if out.channel != "email":
                await q.put(out)
                await asyncio.sleep(0.01)
                continue
            try:
                msg = EmailMessage()
                msg["From"] = ec.username
                msg["To"] = out.chat_id
                msg["Subject"] = "Graphclaw Response"
                msg.set_content(out.text or "")
                await aiosmtplib.send(
                    msg,
                    hostname=ec.smtp_host,
                    port=ec.smtp_port,
                    username=ec.username,
                    password=ec.password,
                    start_tls=True
                )
            except Exception as e:
                print(f"[email] send error: {e}")

    asyncio.ensure_future(poll_inbox())
    asyncio.ensure_future(send_loop())
    ::py::
}
