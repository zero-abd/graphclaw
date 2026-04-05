# graphclaw/memory/recall.jac
# Recall walkers backed by the current workspace memory/session store.

walker Recall {
    has query: str;
    has limit: int = 10;
    has semantic: bool = False;
    has mem_type: str = "";
    has min_confidence: float = 0.1;

    can search with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import recall
        result_payload = recall(
            query=self.query,
            limit=self.limit,
            semantic=self.semantic,
            mem_type=self.mem_type,
            min_confidence=self.min_confidence,
        )
        ::py::
        report result_payload;
    }
}

walker RecallByType {
    has mem_type: str;
    has limit: int = 20;

    can fetch with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import recall_by_type
        result_payload = recall_by_type(mem_type=self.mem_type, limit=self.limit)
        ::py::
        report result_payload;
    }
}

walker RecallByTopic {
    has topic_name: str;
    has limit: int = 20;

    can fetch with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import recall_by_topic
        result_payload = recall_by_topic(topic_name=self.topic_name, limit=self.limit)
        ::py::
        report result_payload;
    }
}

walker RecallSession {
    has session_id: str;
    has last_n: int = 50;

    can fetch with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import recall_session
        result_payload = recall_session(session_id=self.session_id, last_n=self.last_n)
        ::py::
        report result_payload;
    }
}

walker GetMemoryContext {
    has max_chars: int = 4000;

    can build with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import get_memory_context
        result_payload = get_memory_context(max_chars=self.max_chars)
        ::py::
        report result_payload;
    }
}
