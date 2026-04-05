# graphclaw/memory/dream.jac
# Dream walker -- background graph maintenance (nanobot's "Dream" reimagined)
#
# Instead of rewriting a MEMORY.md blob, Dream walks the graph and:
#   1. Tombstones zero-confidence nodes
#   2. Finds and links contradicting memory pairs
#   3. Merges near-duplicate memories
#   4. Revalidates memories confirmed still accurate
#   5. Extracts new topic tags from untagged memories

import from graphclaw.memory.nodes {
    Memory, Topic, Relates, HasMemory, Tagged
}
import from graphclaw.memory.consolidate { ConsolidateAll }
import from datetime { datetime, timezone }

# -- LLM helpers ---------------------------------------------------------------

sem find_near_duplicates = "Given a list of memory contents, identify groups of memories that express the same fact (near-duplicates). Return indices of memories that should be merged (keep the most specific one).";

obj DuplicateGroup {
    has keep_index: int;
    has drop_indices: list[int];
    has merged_content: str;
}

def find_near_duplicates(memories: list[str]) -> list[DuplicateGroup] by llm();


sem extract_topics_for_memory = "Given a memory content string, return 1-3 short topic tags (lowercase, no spaces) that best categorize it.";

def extract_topics_for_memory(content: str) -> list[str] by llm();


sem is_memory_still_valid = "Given a memory fact, determine if it is likely still accurate and relevant after significant time has passed. Return True if it is likely still valid, False if it is time-sensitive or probably outdated.";

def is_memory_still_valid(content: str) -> bool by llm();


sem find_relationship = "Given two memory contents that are related but not contradicting or identical, classify their relationship. Return one of: related_to, refines, derived_from, supersedes.";

def find_relationship(mem_a: str, mem_b: str) -> str by llm();

# -- Dream walker ---------------------------------------------------------------

walker Dream {
    has max_memories: int = 100;
    has dry_run: bool = False;

    has _tombstoned: int = 0;
    has _merged: int = 0;
    has _revalidated: int = 0;
    has _linked: int = 0;
    has _tagged: int = 0;

    can run with `root() entry {
        # Step 0: consolidate any pending sessions first
        ConsolidateAll(max_sessions=20) spawn here;

        live_mems = [here -->(:HasMemory:)--> (:Memory)][? tombstoned == False];
        live_mems.sort(key=lambda m: m.effective_confidence());
        batch = live_mems[:self.max_memories];

        # -- Step 1: Tombstone zero-confidence memories ---------------------
        for m in batch {
            if m.is_stale() {
                if not self.dry_run { m.tombstoned = True; }
                self._tombstoned += 1;
            }
        }
        live_batch = [m for m in batch if not m.tombstoned];

        # -- Step 2: Merge near-duplicates ----------------------------------
        contents = [m.content for m in live_batch];
        dup_groups = find_near_duplicates(contents);
        for group in dup_groups {
            keep = live_batch[group.keep_index];
            if not self.dry_run {
                keep.content = group.merged_content;
                keep.touch();
                for drop_i in group.drop_indices {
                    live_batch[drop_i].tombstoned = True;
                    self._merged += 1;
                }
            }
        }
        live_batch = [m for m in live_batch if not m.tombstoned];

        # -- Step 3: Link related memory pairs ------------------------------
        # Only check pairs that don't already have a Relates edge
        for i in range(len(live_batch)) {
            for j in range(i + 1, min(i + 6, len(live_batch))) {
                m_a = live_batch[i];
                m_b = live_batch[j];
                already_linked = [m_a -->(:Relates:)--> (:Memory)][? id == m_b.id];
                if not already_linked {
                    from graphclaw.memory.consolidate import detect_contradiction;
                    if detect_contradiction(m_a.content, m_b.content) {
                        rel = "contradicts";
                    } else {
                        rel = find_relationship(m_a.content, m_b.content);
                    }
                    if not self.dry_run {
                        m_a +:Relates(relationship=rel, weight=1.0):+> m_b;
                        self._linked += 1;
                    }
                }
            }
        }

        # -- Step 4: Revalidate stable memories ----------------------------
        for m in live_batch {
            eff = m.effective_confidence();
            if 0.2 <= eff <= 0.6 {   # in the decay zone -- worth checking
                if is_memory_still_valid(m.content) {
                    if not self.dry_run {
                        m.touch();
                        self._revalidated += 1;
                    }
                }
            }
        }

        # -- Step 5: Auto-tag untagged memories ----------------------------
        for m in live_batch {
            existing_tags = [here -->][?:Topic];
            tagged_mems = [];
            for tag in existing_tags {
                tagged = [tag -->(:Tagged:)--> (:Memory)][? id == m.id];
                if tagged { tagged_mems.append(tag); }
            }
            if not tagged_mems {
                tags = extract_topics_for_memory(m.content);
                for tag_name in tags {
                    if not self.dry_run {
                        existing = [here -->][?:Topic][? name == tag_name];
                        if existing {
                            t = existing[0];
                        } else {
                            t = Topic(name=tag_name);
                            here ++> t;
                        }
                        t +:Tagged:+> m;
                        self._tagged += 1;
                    }
                }
            }
        }

        report {
            "tombstoned": self._tombstoned,
            "merged": self._merged,
            "revalidated": self._revalidated,
            "linked": self._linked,
            "tagged": self._tagged,
            "timestamp": datetime.now(timezone.utc).isoformat()
        };
    }
}
