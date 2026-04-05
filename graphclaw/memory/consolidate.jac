# graphclaw/memory/consolidate.jac
# Session consolidation walkers backed by workspace storage.

walker Consolidate {
    has session_id: str;

    can run with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import consolidate_session
        result_payload = consolidate_session(session_id=self.session_id)
        ::py::
        report result_payload;
    }
}

walker ConsolidateAll {
    has max_sessions: int = 10;

    can run with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import consolidate_all
        result_payload = consolidate_all(max_sessions=self.max_sessions)
        ::py::
        report result_payload;
    }
}
