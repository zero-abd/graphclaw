# graphclaw/memory/recall.jac
# Recall walkers — substring (fast) + semantic (by llm) dual-mode

import from graphclaw.memory.nodes { Memory, Topic, MemoryType, HasMemory, Tagged };

# ── Semantic relevance check (used when semantic=True) ─────────────────────────

def is_semantically_relevant(query: str, content: str) -> bool by llm();

# ── Main recall walker ─────────────────────────────────────────────────────────

walker Recall {
    has query: str;
    has limit: int = 10;
    has semantic: bool = False;           # user can request semantic mode
    has mem_type: str = "";               # optional type filter
    has min_confidence: float = 0.1;      # skip near-zero confidence nodes

    can search with `root entry {
        # Pull all live memories
        all_mems = [here -->(:HasMemory:)--> (:Memory)][? tombstoned == False];

        # Type filter
        if self.mem_type {
            all_mems = all_mems[? mem_type == self.mem_type];
        }

        # Confidence floor
        candidates = [];
        for m in all_mems {
            if m.effective_confidence() >= self.min_confidence {
                candidates.append(m);
            }
        }

        # Substring pass (always run first — fast)
        q_lower = self.query.lower();
        substring_hits = [m for m in candidates if q_lower in m.content.lower()];

        # Semantic pass (optional, runs on remainder)
        semantic_hits = [];
        if self.semantic {
            remainder = [m for m in candidates if m not in substring_hits];
            for m in remainder {
                if is_semantically_relevant(self.query, m.content) {
                    semantic_hits.append(m);
                }
            }
        }

        # Merge, deduplicate, sort by effective_confidence desc, cap at limit
        combined = substring_hits + semantic_hits;
        seen_ids = set();
        unique = [];
        for m in combined {
            if m.id not in seen_ids {
                seen_ids.add(m.id);
                unique.append(m);
            }
        }
        unique.sort(key=lambda m: m.effective_confidence(), reverse=True);
        results = unique[:self.limit];

        report [{"id": m.id, "content": m.content, "mem_type": m.mem_type,
                 "confidence": m.effective_confidence()} for m in results];
    }
}

# ── Recall by type ─────────────────────────────────────────────────────────────

walker RecallByType {
    has mem_type: str;
    has limit: int = 20;

    can fetch with `root entry {
        mems = [here -->(:HasMemory:)--> (:Memory)][
            ? mem_type == self.mem_type and tombstoned == False
        ];
        mems.sort(key=lambda m: m.effective_confidence(), reverse=True);
        report [{"id": m.id, "content": m.content, "confidence": m.effective_confidence()}
                for m in mems[:self.limit]];
    }
}

# ── Recall by topic ────────────────────────────────────────────────────────────

walker RecallByTopic {
    has topic_name: str;
    has limit: int = 20;

    can fetch with `root entry {
        topics = [here -->][?:Topic][? name == self.topic_name];
        if not topics { report []; disengage; }

        mems = [topics[0] -->(:Tagged:)--> (:Memory)][? tombstoned == False];
        mems.sort(key=lambda m: m.effective_confidence(), reverse=True);
        report [{"id": m.id, "content": m.content, "confidence": m.effective_confidence()}
                for m in mems[:self.limit]];
    }
}

# ── Recall session turns ───────────────────────────────────────────────────────

walker RecallSession {
    has session_id: str;
    has last_n: int = 50;

    can fetch with `root entry {
        import from graphclaw.memory.nodes { Session, Turn, HasSession, HasTurn };
        sessions = [here -->(:HasSession:)--> (:Session)][
            ? session_id == self.session_id
        ];
        if not sessions { report []; disengage; }

        turns = [sessions[0] -->(:HasTurn:)--> (:Turn)];
        turns.sort(key=lambda t: t.timestamp);
        recent = turns[-self.last_n:];
        report [{"role": t.role, "content": t.content, "timestamp": t.timestamp}
                for t in recent];
    }
}

# ── Get all memories as context string (for system prompt injection) ───────────

walker GetMemoryContext {
    has max_chars: int = 4000;

    can build with `root entry {
        mems = [here -->(:HasMemory:)--> (:Memory)][? tombstoned == False];
        mems.sort(key=lambda m: m.effective_confidence(), reverse=True);

        lines = [];
        total = 0;
        for m in mems {
            line = f"[{m.mem_type}] {m.content}";
            total += len(line);
            if total > self.max_chars { break; }
            lines.append(line);
        }
        report "\n".join(lines);
    }
}
