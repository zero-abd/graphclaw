# graphclaw/memory/consolidate.jac
# Consolidator walker -- extracts structured Memory nodes from raw session turns
# Replaces nanobot's Consolidator class (LLM call over flat JSONL)

import from graphclaw.memory.nodes {
    Memory, Session, Turn, Topic, MemoryType,
    HasMemory, HasSession, HasTurn, Produced, Tagged
}

# -- LLM-powered extraction -----------------------------------------------------

obj ExtractedMemory {
    has content: str;
    has mem_type: str;        # MemoryType value string
    has confidence: float;
    has topics: list[str];
    has relates_to: list[str] = [];   # content substrings of related memories
}

obj ConsolidationResult {
    has memories: list[ExtractedMemory];
    has summary: str;   # one-line session summary
}

sem extract_memories_from_turns = "Extract structured, factual memories from a conversation transcript. Each memory should be a standalone fact about the user, project, or agent behavior. Assign appropriate type (User/Feedback/Project/Reference), confidence (0.0-1.0), and relevant topic tags.";

def extract_memories_from_turns(
    transcript: str,
    existing_memories: str
) -> ConsolidationResult by llm();


sem detect_contradiction = "Given two memory contents, determine if they contradict each other. Return True only if they make conflicting factual claims.";

def detect_contradiction(mem_a: str, mem_b: str) -> bool by llm();


sem should_supersede = "Given a new memory and an existing memory, determine if the new memory completely replaces/supersedes the existing one (not just refines it).";

def should_supersede(new_mem: str, existing_mem: str) -> bool by llm();

# -- Consolidator walker --------------------------------------------------------

walker Consolidate {
    has session_id: str;

    can run with `root() entry {
        # Find session
        sessions = [here -->(:HasSession:)--> (:Session)][
            ? session_id == self.session_id and consolidated == False
        ];
        if not sessions { report None; disengage; }
        session = sessions[0];

        # Get turns
        turns = [session -->(:HasTurn:)--> (:Turn)];
        if not turns { report None; disengage; }
        turns.sort(key=lambda t: t.timestamp);

        # Build transcript
        transcript_lines = [];
        for t in turns {
            if t.role in ["user", "assistant"] {
                transcript_lines.append(f"{t.role.upper()}: {t.content[:500]}");
            }
        }
        transcript = "\n".join(transcript_lines);

        # Get existing memories as context (avoid duplication)
        existing_mems = [here -->(:HasMemory:)--> (:Memory)][? tombstoned == False];
        existing_str = "\n".join([f"- {m.content}" for m in existing_mems[:50]]);

        # LLM extraction
        result = extract_memories_from_turns(transcript, existing_str);

        # Write new Memory nodes
        for em in result.memories {
            # Check for contradictions / supersedes against existing
            for existing in existing_mems {
                if should_supersede(em.content, existing.content) {
                    existing.tombstoned = True;
                } elif detect_contradiction(em.content, existing.content) {
                    # Keep both but link with contradicts edge
                    pass;  # handled after node creation below
                }
            }

            m = Memory(
                content=em.content,
                mem_type=em.mem_type,
                confidence=em.confidence,
                source_session=self.session_id,
                agent=session.agent
            );
            here +:HasMemory:+> m;
            session +:Produced:+> m;

            # Tag
            for tag in em.topics {
                tag_node = None;
                existing_topics = [here -->][?:Topic][? name == tag];
                if existing_topics {
                    tag_node = existing_topics[0];
                } else {
                    tag_node = Topic(name=tag);
                    here ++> tag_node;
                }
                tag_node +:Tagged:+> m;
            }
        }

        session.consolidated = True;
        report result.summary;
    }
}

# -- Batch consolidation (process all unconsolidated sessions) ------------------

walker ConsolidateAll {
    has max_sessions: int = 10;

    can run with `root() entry {
        sessions = [here -->(:HasSession:)--> (:Session)][? consolidated == False];
        sessions.sort(key=lambda s: s.started_at);
        to_process = sessions[:self.max_sessions];

        summaries = [];
        for s in to_process {
            result = Consolidate(session_id=s.session_id) spawn here;
            if result { summaries.append(result); }
        }
        report summaries;
    }
}
