"""Async message bus for channel <-> agent communication."""
from __future__ import annotations
import asyncio
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, Callable, Awaitable, List


@dataclass
class InboundMessage:
    channel: str
    chat_id: str
    user_id: str
    text: str
    media: Optional[List[str]] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class OutboundMessage:
    channel: str
    chat_id: str
    text: str
    reply_to: Optional[str] = None
    media: Optional[List[str]] = None
    metadata: Dict[str, Any] = field(default_factory=dict)


class MessageBus:
    """Singleton async message bus."""

    def __init__(self) -> None:
        self._inbound: Optional[asyncio.Queue] = None
        self._outbound: Optional[asyncio.Queue] = None
        self._handlers: List[Callable[[InboundMessage], Awaitable[None]]] = []

    def _ensure_queues(self) -> None:
        if self._inbound is None:
            self._inbound = asyncio.Queue()
        if self._outbound is None:
            self._outbound = asyncio.Queue()

    def publish_inbound(self, msg: InboundMessage) -> None:
        self._ensure_queues()
        self._inbound.put_nowait(msg)

    def publish_outbound(self, msg: OutboundMessage) -> None:
        self._ensure_queues()
        self._outbound.put_nowait(msg)

    def get_inbound_queue(self) -> asyncio.Queue:
        self._ensure_queues()
        return self._inbound

    def get_outbound_queue(self) -> asyncio.Queue:
        self._ensure_queues()
        return self._outbound

    def on_inbound(self, handler: Callable[[InboundMessage], Awaitable[None]]) -> None:
        self._handlers.append(handler)


# Module-level singleton
bus = MessageBus()
