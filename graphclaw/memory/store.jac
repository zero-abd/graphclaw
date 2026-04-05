# graphclaw/memory/store.jac
# Walkers for writing to the memory graph

import from graphclaw.memory.nodes {
    Memory, Session, Topic, Turn, UserProfile,
    MemoryType, Relates, Produced, Tagged, HasSession, HasMemory, HasTurn, HasProfile
};
import from datetime { datetime, timezone };
import from uuid { uuid4 };

# ── Store a memory node ────────────────────────────────────────────────────────

walker StoreMemory {
    has content: str;
    has mem_type: str = MemoryType.USER.value;
    has confidence: float = 1.0;
    has source_session: str = "";
    has agent: str = "";
    has _result_id: str = "";

    can store with `root entry {
        m = Memory(
            content=self.content,
            mem_type=self.mem_type,
            confidence=self.confidence,
            source_session=self.source_session,
            agent=self.agent
        );
        here +:HasMemory:+> m;
        self._result_id = m.id;
        report m.id;
    }
}

# ── Link two memories ──────────────────────────────────────────────────────────

walker LinkMemories {
    has from_id: str;
    has to_id: str;
    has relationship: str = "related_to";
    has weight: float = 1.0;

    can link with `root entry {
        mems = [here -->(:HasMemory:)--> (:Memory)][? id == self.from_id];
        targets = [here -->(:HasMemory:)--> (:Memory)][? id == self.to_id];
        if mems and targets {
            mems[0] +:Relates(relationship=self.relationship, weight=self.weight):+> targets[0];
            report True;
        }
        report False;
    }
}

# ── Tag a memory with a topic ──────────────────────────────────────────────────

walker TagMemory {
    has memory_id: str;
    has topic_name: str;

    can tag with `root entry {
        mems = [here -->(:HasMemory:)--> (:Memory)][? id == self.memory_id];
        if not mems { report False; disengage; }
        mem = mems[0];

        # Reuse existing topic node or create one
        existing_topics = [here -->][?:Topic][? name == self.topic_name];
        if existing_topics {
            topic = existing_topics[0];
        } else {
            topic = Topic(name=self.topic_name);
            here ++> topic;
        }
        topic +:Tagged:+> mem;
        report True;
    }
}

# ── Revalidate (reset decay clock) ────────────────────────────────────────────

walker RevalidateMemory {
    has memory_id: str;

    can revalidate with `root entry {
        mems = [here -->(:HasMemory:)--> (:Memory)][? id == self.memory_id];
        if mems {
            mems[0].touch();
            report True;
        }
        report False;
    }
}

# ── Tombstone (soft-delete) ────────────────────────────────────────────────────

walker TombstoneMemory {
    has memory_id: str;

    can tombstone with `root entry {
        mems = [here -->(:HasMemory:)--> (:Memory)][? id == self.memory_id];
        if mems {
            mems[0].tombstoned = True;
            mems[0].updated_at = datetime.now(timezone.utc).isoformat();
            report True;
        }
        report False;
    }
}

# ── Record a session ───────────────────────────────────────────────────────────

walker StartSession {
    has channel: str;
    has chat_id: str;
    has user_id: str = "";
    has agent: str = "coordinator";
    has model: str = "";

    can start with `root entry {
        s = Session(
            channel=self.channel,
            chat_id=self.chat_id,
            user_id=self.user_id,
            agent=self.agent,
            model=self.model
        );
        here +:HasSession:+> s;
        report s.session_id;
    }
}

# ── Append a turn to an existing session ──────────────────────────────────────

walker AppendTurn {
    has session_id: str;
    has role: str;
    has content: str;
    has tool_name: str = "";
    has tool_result: str = "";
    has token_count: int = 0;

    can append with `root entry {
        sessions = [here -->(:HasSession:)--> (:Session)][? session_id == self.session_id];
        if not sessions { report None; disengage; }
        s = sessions[0];
        t = Turn(
            role=self.role,
            content=self.content,
            tool_name=self.tool_name,
            tool_result=self.tool_result,
            token_count=self.token_count
        );
        s +:HasTurn:+> t;
        s +:Produced:+> t;
        s.turns += 1;
        report t.turn_id;
    }
}

# ── Upsert user profile ────────────────────────────────────────────────────────

walker UpsertProfile {
    has display_name: str = "";
    has timezone: str = "UTC";
    has preferred_model: str = "";

    can upsert with `root entry {
        profiles = [here -->(:HasProfile:)--> (:UserProfile)];
        if profiles {
            p = profiles[0];
        } else {
            p = UserProfile();
            here +:HasProfile:+> p;
        }
        if self.display_name { p.display_name = self.display_name; }
        if self.timezone { p.timezone = self.timezone; }
        if self.preferred_model { p.preferred_model = self.preferred_model; }
        report p;
    }
}
