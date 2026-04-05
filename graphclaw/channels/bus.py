"""Async message bus for channel <-> agent communication."""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Dict, List, Optional


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
        self._inbound: Optional[asyncio.Queue[InboundMessage]] = None
        self._outbound_all: Optional[asyncio.Queue[OutboundMessage]] = None
        self._outbound_by_channel: Dict[str, asyncio.Queue[OutboundMessage]] = {}
        self._handlers: List[Callable[[InboundMessage], Awaitable[None]]] = []

    def _ensure_queues(self) -> None:
        if self._inbound is None:
            self._inbound = asyncio.Queue()
        if self._outbound_all is None:
            self._outbound_all = asyncio.Queue()

    def _get_channel_queue(self, channel: str) -> asyncio.Queue[OutboundMessage]:
        self._ensure_queues()
        if channel not in self._outbound_by_channel:
            self._outbound_by_channel[channel] = asyncio.Queue()
        return self._outbound_by_channel[channel]

    def publish_inbound(self, msg: InboundMessage) -> None:
        self._ensure_queues()
        self._inbound.put_nowait(msg)

    def publish_outbound(self, msg: OutboundMessage) -> None:
        self._ensure_queues()
        self._outbound_all.put_nowait(msg)
        self._get_channel_queue(msg.channel).put_nowait(msg)

    def get_inbound_queue(self) -> asyncio.Queue[InboundMessage]:
        self._ensure_queues()
        return self._inbound

    def get_outbound_queue(self, channel: Optional[str] = None) -> asyncio.Queue[OutboundMessage]:
        self._ensure_queues()
        if channel:
            return self._get_channel_queue(channel)
        return self._outbound_all

    def on_inbound(self, handler: Callable[[InboundMessage], Awaitable[None]]) -> None:
        self._handlers.append(handler)


bus = MessageBus()
