# graphclaw/channels/bus.jac
# Async message bus -- all channels publish/subscribe through this

import from asyncio { Queue, get_event_loop }
import from dataclasses { dataclass, field }
import from typing { Optional, Callable, Awaitable }

obj InboundMessage {
    has channel: str;
    has chat_id: str;
    has user_id: str = "";
    has text: str = "";
    has attachments: list[dict] = [];
    has raw: dict = {};
    has session_id: str = "";   # filled by loop after session lookup
}

obj OutboundMessage {
    has channel: str;
    has chat_id: str;
    has text: str = "";
    has parse_mode: str = "markdown";   # markdown | html | plain
    has reply_to_id: str = "";
    has attachments: list[dict] = [];
    has stream_token: bool = False;     # True if this is a streaming chunk
    has final: bool = True;             # False if more chunks coming
}

obj MessageBus {
    has _inbound: Any = None;
    has _outbound: Any = None;
    has _handlers: dict = {};   # channel_name -> handler coroutine

    def postinit {
        ::py::
        import asyncio
        self._inbound = asyncio.Queue()
        self._outbound = asyncio.Queue()
        ::py::
    }

    def publish_inbound(msg: InboundMessage) {
        ::py::
        import asyncio
        asyncio.get_event_loop().call_soon_threadsafe(
            self._inbound.put_nowait, msg
        )
        ::py::
    }

    def publish_outbound(msg: OutboundMessage) {
        ::py::
        import asyncio
        asyncio.get_event_loop().call_soon_threadsafe(
            self._outbound.put_nowait, msg
        )
        ::py::
    }

    def register_channel(name: str, handler) {
        self._handlers[name] = handler;
    }

    def get_inbound_queue() -> Any { return self._inbound; }
    def get_outbound_queue() -> Any { return self._outbound; }
}

# Global bus singleton
glob bus: MessageBus = MessageBus();
