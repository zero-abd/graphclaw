# graphclaw/memory/nodes.jac
# Graph schema — all memory lives here as OSP nodes connected to root

import from datetime { datetime, timezone };
import from uuid { uuid4 };

# ── Memory Types ──────────────────────────────────────────────────────────────

enum MemoryType {
    USER = "User",          # Facts about the user — role, preferences, goals
    FEEDBACK = "Feedback",  # Behavioral corrections and guidance
    PROJECT = "Project",    # Architecture, decisions, deadlines
    REFERENCE = "Reference" # Pointers to external resources
}

# ── Nodes ─────────────────────────────────────────────────────────────────────

node Memory {
    has id: str = "";
    has content: str = "";
    has mem_type: str = MemoryType.USER.value;
    has confidence: float = 1.0;
    has decay_rate: float = 0.01;       # loses 1% per day by default
    has created_at: str = "";
    has updated_at: str = "";
    has last_validated_at: str = "";
    has source_session: str = "";       # session_id that produced this
    has agent: str = "";                # which agent wrote this memory
    has tombstoned: bool = False;       # soft-delete

    def postinit {
        now = datetime.now(timezone.utc).isoformat();
        if not self.id { self.id = str(uuid4()); }
        if not self.created_at { self.created_at = now; }
        if not self.updated_at { self.updated_at = now; }
        if not self.last_validated_at { self.last_validated_at = now; }
    }

    def effective_confidence() -> float {
        from datetime import datetime, timezone, timedelta;
        now = datetime.now(timezone.utc);
        last = datetime.fromisoformat(self.last_validated_at);
        days = (now - last).total_seconds() / 86400.0;
        decayed = self.confidence - (self.decay_rate * days);
        if decayed < 0.0 { return 0.0; }
        if decayed > 1.0 { return 1.0; }
        return decayed;
    }

    def touch {
        self.last_validated_at = datetime.now(timezone.utc).isoformat();
        self.updated_at = self.last_validated_at;
    }

    def is_stale() -> bool {
        return self.effective_confidence() <= 0.0;
    }
}

node Session {
    has session_id: str = "";
    has channel: str = "";
    has chat_id: str = "";
    has user_id: str = "";
    has agent: str = "";
    has model: str = "";
    has started_at: str = "";
    has turns: int = 0;
    has consolidated: bool = False;

    def postinit {
        if not self.session_id { self.session_id = str(uuid4()); }
        if not self.started_at {
            self.started_at = datetime.now(timezone.utc).isoformat();
        }
    }
}

node Topic {
    has name: str = "";
}

node Turn {
    has turn_id: str = "";
    has role: str = "";       # "user" | "assistant" | "tool"
    has content: str = "";
    has tool_name: str = "";
    has tool_result: str = "";
    has timestamp: str = "";
    has token_count: int = 0;

    def postinit {
        if not self.turn_id { self.turn_id = str(uuid4()); }
        if not self.timestamp {
            self.timestamp = datetime.now(timezone.utc).isoformat();
        }
    }
}

# Singleton node — one per user root, holds user-level identity
node UserProfile {
    has display_name: str = "";
    has timezone: str = "UTC";
    has preferred_model: str = "";
    has created_at: str = "";

    def postinit {
        if not self.created_at {
            self.created_at = datetime.now(timezone.utc).isoformat();
        }
    }
}

# ── Edges ─────────────────────────────────────────────────────────────────────

edge Relates {
    has relationship: str = "related_to";
    # relationship options: related_to | contradicts | refines | derived_from | supersedes
    has weight: float = 1.0;
}

edge Produced {}      # (:Session)-[:Produced]->(:Memory | :Turn)
edge Tagged {}        # (:Topic)-[:Tagged]->(:Memory)
edge HasSession {}    # root -[:HasSession]-> (:Session)
edge HasMemory {}     # root -[:HasMemory]->  (:Memory)
edge HasTurn {}       # (:Session)-[:HasTurn]->(:Turn)
edge HasProfile {}    # root -[:HasProfile]-> (:UserProfile)
