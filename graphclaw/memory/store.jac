# graphclaw/memory/store.jac
# Walkers for writing to the memory/session store.

import from graphclaw.memory.nodes { MemoryType }

walker StoreMemory {
    has content: str;
    has mem_type: str = MemoryType.USER.value;
    has confidence: float = 1.0;
    has source_session: str = "";
    has agent: str = "";
    has topics: list[str] = [];

    can store with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import store_memory
        result_payload = store_memory(
            content=self.content,
            mem_type=self.mem_type,
            confidence=self.confidence,
            source_session=self.source_session,
            agent=self.agent,
            topics=list(self.topics),
        )
        ::py::
        report result_payload;
    }
}

walker LinkMemories {
    has from_id: str;
    has to_id: str;
    has relationship: str = "related_to";
    has weight: float = 1.0;

    can link with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import link_memories
        result_payload = link_memories(
            from_id=self.from_id,
            to_id=self.to_id,
            relationship=self.relationship,
            weight=self.weight,
        )
        ::py::
        report result_payload;
    }
}

walker TagMemory {
    has memory_id: str;
    has topic_name: str;

    can tag with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import tag_memory
        result_payload = tag_memory(memory_id=self.memory_id, topic_name=self.topic_name)
        ::py::
        report result_payload;
    }
}

walker RevalidateMemory {
    has memory_id: str;

    can revalidate with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import revalidate_memory
        result_payload = revalidate_memory(memory_id=self.memory_id)
        ::py::
        report result_payload;
    }
}

walker TombstoneMemory {
    has memory_id: str;

    can tombstone with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import tombstone_memory
        result_payload = tombstone_memory(memory_id=self.memory_id)
        ::py::
        report result_payload;
    }
}

walker StartSession {
    has channel: str;
    has chat_id: str;
    has session_id: str = "";
    has user_id: str = "";
    has agent: str = "coordinator";
    has model: str = "";

    can start with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import start_session
        result_payload = start_session(
            session_id=self.session_id,
            channel=self.channel,
            chat_id=self.chat_id,
            user_id=self.user_id,
            agent=self.agent,
            model=self.model,
        )
        ::py::
        report result_payload;
    }
}

walker AppendTurn {
    has session_id: str;
    has role: str;
    has content: str;
    has tool_name: str = "";
    has tool_result: str = "";
    has token_count: int = 0;

    can append with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import append_turn
        result_payload = append_turn(
            session_id=self.session_id,
            role=self.role,
            content=self.content,
            tool_name=self.tool_name,
            tool_result=self.tool_result,
            token_count=self.token_count,
        )
        ::py::
        report result_payload;
    }
}

walker UpsertProfile {
    has display_name: str = "";
    has timezone_name: str = "UTC";
    has preferred_model: str = "";

    can upsert with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import upsert_profile
        result_payload = upsert_profile(
            display_name=self.display_name,
            timezone_name=self.timezone_name,
            preferred_model=self.preferred_model,
        )
        ::py::
        report result_payload;
    }
}
