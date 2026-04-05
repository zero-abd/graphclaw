"""Shared channel auth/pairing helpers for Telegram and Discord."""
from __future__ import annotations

import json
import secrets
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

from graphclaw.config.loader import load_config


PAIRING_CODE_LENGTH = 8
PAIRING_TTL_SECONDS = 3600
MAX_PENDING_REQUESTS = 3
_PAIRING_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


@dataclass
class AuthEvent:
    """Normalized inbound event info for auth decisions."""

    channel: str
    user_id: str
    chat_id: str
    text: str
    is_direct: bool
    username: str = ""
    display_name: str = ""
    is_mentioned: bool = False
    mention_detection_available: bool = False
    channel_name: str = ""
    guild_id: str = ""
    group_id: str = ""


@dataclass
class AuthNotification:
    """Outbound notification produced by the auth layer."""

    chat_id: str
    text: str


@dataclass
class AuthDecision:
    """Result of evaluating an inbound message."""

    allow_publish: bool = False
    responses: list[str] = field(default_factory=list)
    notifications: list[AuthNotification] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


class ChannelAuthManager:
    """Centralized per-channel DM/group auth and pairing flow."""

    def __init__(self, channel: str, channel_config: Optional[dict[str, Any]] = None) -> None:
        self.channel = channel
        cfg = load_config()
        self.channel_config = dict(channel_config or cfg.channels.get(channel, {}) or {})
        self.credentials_dir = Path.home() / ".graphclaw" / "credentials"
        self.credentials_dir.mkdir(parents=True, exist_ok=True)
        self.allow_path = self.credentials_dir / f"{channel}-allowFrom.json"
        self.pairing_path = self.credentials_dir / f"{channel}-pairing.json"

    def startup_warnings(self) -> list[str]:
        warnings: list[str] = [
            f"dm_policy={self.dm_policy!r}; approved DM senders persist in {self.allow_path}",
        ]
        if self.dm_policy == "pairing" and not self.owner_ids:
            warnings.append(
                "pairing approvals are available from the local CLI with "
                f"'pairing approve {self.channel} <code>'; set channels.{self.channel}.owner_ids "
                "only if you also want in-chat approval commands"
            )
        if self.group_policy == "allowlist" and not self._has_any_group_allowlist():
            warnings.append(
                "group_policy='allowlist' with no groups configured; this only blocks group chats — direct messages still work. Add "
                f"channels.{self.channel}.groups (or channels.{self.channel}.guilds for Discord) or switch to 'open'"
            )
        return warnings

    @property
    def dm_policy(self) -> str:
        policy = str(self.channel_config.get("dm_policy", "pairing") or "pairing").strip().lower()
        return policy if policy in {"pairing", "allowlist", "open", "disabled"} else "pairing"

    @property
    def group_policy(self) -> str:
        policy = str(self.channel_config.get("group_policy", "allowlist") or "allowlist").strip().lower()
        return policy if policy in {"allowlist", "open", "disabled"} else "allowlist"

    @property
    def owner_ids(self) -> set[str]:
        configured = self._normalize_values(self.channel_config.get("owner_ids", []))
        if configured:
            return configured
        return self._configured_allow_from()

    def evaluate(self, event: AuthEvent) -> AuthDecision:
        owner_command = self._maybe_handle_owner_command(event)
        if owner_command is not None:
            return owner_command
        if event.is_direct:
            return self._evaluate_dm(event)
        return self._evaluate_group(event)

    def _evaluate_dm(self, event: AuthEvent) -> AuthDecision:
        if self.dm_policy == "disabled":
            return AuthDecision(
                responses=[
                    f"{self.channel.title()} direct messages are disabled. "
                    f"Ask the owner to change channels.{self.channel}.dm_policy to 'pairing', 'allowlist', or 'open'."
                ]
            )

        if self._is_sender_allowed(event, self._effective_allow_from()):
            return AuthDecision(allow_publish=True, metadata={"auth_status": "approved"})

        if self.dm_policy == "open":
            if not self._allowlist_is_open():
                return AuthDecision(
                    responses=[
                        f"{self.channel.title()} dm_policy is 'open', but allow_from is missing '*'. "
                        f"Set channels.{self.channel}.allow_from to ['*'] or use 'pairing'."
                    ]
                )
            return AuthDecision(allow_publish=True, metadata={"auth_status": "open"})

        if self.dm_policy == "allowlist":
            return AuthDecision(
                responses=[
                    f"You're not approved to message this {self.channel.title()} bot yet. "
                    f"Ask the owner to add your ID to channels.{self.channel}.allow_from or switch dm_policy to 'pairing'."
                ]
            )

        pairing = self._get_or_create_pairing_request(event)
        if pairing is None:
            return AuthDecision(
                responses=[
                    f"There are already {MAX_PENDING_REQUESTS} pending {self.channel.title()} pairing requests. "
                    "Ask the owner to approve or wait for older requests to expire before trying again."
                ],
                metadata={"auth_status": "pending_limit_reached"},
            )
        request, was_created = pairing
        owner_hint = (
            f"Approve it from the local CLI with 'pairing approve {self.channel} {request['code']}'."
        )
        if self.owner_ids:
            owner_hint += (
                f" Owners can also send 'pairing approve {request['code']}' "
                f"from an allowed {self.channel.title()} account."
            )
        status_line = "Owner approval is required before we can chat here."
        if not was_created:
            status_line = "Your earlier pairing request is still pending approval."
        return AuthDecision(
            responses=[
                status_line,
                f"Pairing code: {request['code']}",
                owner_hint,
                f"Owners can inspect pending requests with 'pairing list {self.channel}'.",
            ],
            metadata={"auth_status": "pending", "pairing_code": request["code"]},
        )

    def _evaluate_group(self, event: AuthEvent) -> AuthDecision:
        if self.group_policy == "disabled":
            return AuthDecision()

        if self.group_policy == "allowlist" and not self._is_group_allowed(event):
            return AuthDecision()

        group_senders = self._normalize_values(
            self.channel_config.get("group_allow_from", [])
            or self.channel_config.get("allow_from", [])
            or self.channel_config.get("allowed_ids", [])
        )
        if group_senders and not self._is_sender_allowed(event, group_senders):
            return AuthDecision()

        require_mention = self._group_requires_mention(event)
        if require_mention and event.mention_detection_available and not event.is_mentioned:
            return AuthDecision(metadata={"auth_status": "group_waiting_for_mention"})

        return AuthDecision(
            allow_publish=True,
            metadata={
                "auth_status": "approved",
                "is_group": True,
                "was_mentioned": event.is_mentioned,
            },
        )

    def _maybe_handle_owner_command(self, event: AuthEvent) -> Optional[AuthDecision]:
        if not self._is_sender_allowed(event, self.owner_ids):
            return None

        text = (event.text or "").strip()
        if not text:
            return None
        normalized = text.lstrip("/").strip()
        parts = normalized.split()
        if not parts:
            return None

        head = parts[0].lower()
        if head in {"pairing", "pair"} and len(parts) >= 2:
            sub = parts[1].lower()
            if sub == "list":
                return AuthDecision(responses=[self._render_pending_requests()])
            if sub == "approve" and len(parts) >= 3:
                return self._approve_pairing(parts[2])
            return AuthDecision(
                responses=["Usage: pairing list | pairing approve <code>"]
            )

        if head == "approve" and len(parts) >= 2:
            return self._approve_pairing(parts[1])

        return None

    def _approve_pairing(self, raw_code: str) -> AuthDecision:
        code = self._normalize_code(raw_code)
        pending = self._read_pairings()
        request = pending.pop(code, None)
        if request is None:
            return AuthDecision(
                responses=[f"No pending {self.channel.title()} pairing request found for code {code}."]
            )

        allow_from = self._read_allow_from()
        allow_from.add(str(request["user_id"]))
        self._write_allow_from(allow_from)
        self._write_pairings(pending)

        return AuthDecision(
            responses=[
                f"Approved {self.channel.title()} sender {request['user_id']} for future DMs.",
                f"Stored allowlist: {self.allow_path}",
            ],
            notifications=[
                AuthNotification(
                    chat_id=str(request["chat_id"]),
                    text=(
                        f"✅ Your {self.channel.title()} access request has been approved. "
                        "You can send messages now."
                    ),
                )
            ],
            metadata={"auth_status": "approved", "approved_user_id": request["user_id"]},
        )

    def _render_pending_requests(self) -> str:
        pending = self._read_pairings()
        if not pending:
            return f"No pending {self.channel.title()} pairing requests."
        lines = [f"Pending {self.channel.title()} pairing requests:"]
        for code, request in sorted(pending.items()):
            created = str(request.get("created_at", "unknown"))
            display_name = request.get("display_name") or request.get("username") or request["user_id"]
            lines.append(
                f"- {code}: {display_name} (user_id={request['user_id']}, chat_id={request['chat_id']}, created_at={created})"
            )
        lines.append("Approve with: pairing approve <code>")
        return "\n".join(lines)

    def _get_or_create_pairing_request(self, event: AuthEvent) -> tuple[dict[str, Any], bool] | None:
        pending = self._read_pairings()
        existing_code = next(
            (
                code
                for code, request in pending.items()
                if str(request.get("user_id")) == event.user_id and str(request.get("chat_id")) == event.chat_id
            ),
            "",
        )
        if existing_code:
            request = pending[existing_code]
            return request, False
        if len(pending) >= MAX_PENDING_REQUESTS:
            return None
        request = {
            "code": self._generate_code(),
            "user_id": event.user_id,
            "chat_id": event.chat_id,
            "username": event.username,
            "display_name": event.display_name,
            "created_at": datetime.now(UTC).isoformat(),
            "last_text": event.text[:500],
        }
        pending[request["code"]] = request
        self._write_pairings(pending)
        return request, True

    def _generate_code(self) -> str:
        pending = self._read_pairings()
        while True:
            code = "".join(secrets.choice(_PAIRING_ALPHABET) for _ in range(PAIRING_CODE_LENGTH))
            if code not in pending:
                return code

    def _allowlist_is_open(self) -> bool:
        values = self._configured_allow_from()
        persisted = self._read_allow_from()
        return "*" in values or "*" in persisted

    def _effective_allow_from(self) -> set[str]:
        return self._configured_allow_from() | self._read_allow_from()

    def _configured_allow_from(self) -> set[str]:
        configured = list(self.channel_config.get("allow_from", [])) + list(self.channel_config.get("allowed_ids", []))
        return self._normalize_values(configured)

    def _is_sender_allowed(self, event: AuthEvent, allowlist: Iterable[str]) -> bool:
        normalized = {self._normalize_identity(value) for value in allowlist if str(value).strip()}
        candidates = self._identity_candidates(event)
        return "*" in normalized or bool(candidates & normalized)

    def _identity_candidates(self, event: AuthEvent) -> set[str]:
        candidates = {
            event.user_id,
            self._normalize_identity(event.user_id),
            self._normalize_identity(f"{self.channel}:{event.user_id}"),
        }
        if self.channel == "telegram":
            candidates.add(self._normalize_identity(f"tg:{event.user_id}"))
        username = event.username.lstrip("@").strip() if event.username else ""
        if username:
            candidates.add(self._normalize_identity(username))
            candidates.add(self._normalize_identity(f"@{username}"))
        return {value for value in candidates if value}

    def _is_group_allowed(self, event: AuthEvent) -> bool:
        if self.channel == "discord":
            return self._is_discord_channel_allowed(event)
        return self._is_simple_group_allowed(event.group_id or event.chat_id)

    def _is_simple_group_allowed(self, group_id: str) -> bool:
        groups = self.channel_config.get("groups", {}) or {}
        if "*" in groups:
            wildcard = groups["*"]
            if isinstance(wildcard, bool):
                return wildcard
            return bool(wildcard.get("allow", True))
        entry = groups.get(str(group_id))
        if entry is None:
            return False
        if isinstance(entry, bool):
            return entry
        return bool(entry.get("allow", True))

    def _is_discord_channel_allowed(self, event: AuthEvent) -> bool:
        guilds = self.channel_config.get("guilds", {}) or {}
        guild_cfg = guilds.get(event.guild_id) or guilds.get("*") or {}
        if not guild_cfg:
            return False
        if isinstance(guild_cfg, bool):
            return guild_cfg
        if guild_cfg.get("allow") is True and not guild_cfg.get("channels"):
            return True
        channels = guild_cfg.get("channels", {}) or {}
        channel_cfg = channels.get(event.chat_id) or channels.get(event.channel_name) or channels.get("*")
        if channel_cfg is None:
            return False
        if isinstance(channel_cfg, bool):
            return channel_cfg
        return bool(channel_cfg.get("allow", True))

    def _group_requires_mention(self, event: AuthEvent) -> bool:
        if self.channel == "discord":
            guilds = self.channel_config.get("guilds", {}) or {}
            guild_cfg = guilds.get(event.guild_id) or guilds.get("*") or {}
            if isinstance(guild_cfg, dict):
                channels = guild_cfg.get("channels", {}) or {}
                channel_cfg = channels.get(event.chat_id) or channels.get(event.channel_name) or channels.get("*")
                if isinstance(channel_cfg, dict) and "require_mention" in channel_cfg:
                    return bool(channel_cfg["require_mention"])
                if isinstance(channel_cfg, dict) and "requireMention" in channel_cfg:
                    return bool(channel_cfg["requireMention"])
        groups = self.channel_config.get("groups", {}) or {}
        entry = groups.get(str(event.group_id or event.chat_id)) or groups.get("*") or {}
        if isinstance(entry, dict):
            if "require_mention" in entry:
                return bool(entry["require_mention"])
            if "requireMention" in entry:
                return bool(entry["requireMention"])
        return True

    def _has_any_group_allowlist(self) -> bool:
        if self.channel == "discord":
            return bool(self.channel_config.get("guilds"))
        return bool(self.channel_config.get("groups"))

    def _read_allow_from(self) -> set[str]:
        payload = self._read_json(self.allow_path, {"allow_from": []})
        return self._normalize_values(payload.get("allow_from", []))

    def _write_allow_from(self, values: Iterable[str]) -> None:
        payload = {"allow_from": sorted({str(value) for value in values if str(value).strip()})}
        self._write_json(self.allow_path, payload)

    def _read_pairings(self) -> dict[str, dict[str, Any]]:
        payload = self._read_json(self.pairing_path, {"pending": {}})
        pending = {self._normalize_code(code): dict(request) for code, request in (payload.get("pending", {}) or {}).items()}
        now = datetime.now(UTC)
        filtered = {}
        expired = False
        for code, request in pending.items():
            created_at = str(request.get("created_at", ""))
            try:
                created = datetime.fromisoformat(created_at)
                if created.tzinfo is None:
                    created = created.replace(tzinfo=UTC)
            except ValueError:
                created = now
            age_seconds = (now - created).total_seconds()
            if age_seconds > PAIRING_TTL_SECONDS:
                expired = True
                continue
            filtered[code] = request
        if expired:
            self._write_pairings(filtered)
        return filtered

    def _write_pairings(self, pending: dict[str, dict[str, Any]]) -> None:
        payload = {"pending": pending}
        self._write_json(self.pairing_path, payload)

    def _read_json(self, path: Path, default: dict[str, Any]) -> dict[str, Any]:
        if not path.exists():
            return dict(default)
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return dict(default)

    def _write_json(self, path: Path, payload: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = path.with_suffix(f"{path.suffix}.tmp")
        tmp_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        tmp_path.replace(path)

    def _normalize_values(self, values: Iterable[Any]) -> set[str]:
        return {self._normalize_identity(value) for value in values if str(value).strip()}

    def _normalize_identity(self, value: Any) -> str:
        return str(value).strip().lower()

    def _normalize_code(self, value: Any) -> str:
        return "".join(ch for ch in str(value).upper() if ch.isalnum())


def list_pending_requests(channel: str) -> str:
    manager = ChannelAuthManager(channel)
    return manager._render_pending_requests()


def approve_pairing_request(channel: str, code: str) -> AuthDecision:
    manager = ChannelAuthManager(channel)
    return manager._approve_pairing(code)
