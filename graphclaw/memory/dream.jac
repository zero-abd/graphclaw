# graphclaw/memory/dream.jac
# Background maintenance walker backed by workspace storage.

walker Dream {
    has max_memories: int = 100;
    has dry_run: bool = False;

    can run with Root entry {
        result_payload = None;
        ::py::
        from graphclaw.memory.backend import dream_run
        result_payload = dream_run(max_memories=self.max_memories, dry_run=self.dry_run)
        ::py::
        report result_payload;
    }
}
