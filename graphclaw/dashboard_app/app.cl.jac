import "./dashboard.css";
cl import from "./graph_helpers.js" { GraphMemoryCanvas, fetchDashboardMemory }
sv import from graphclaw.dashboard { dashboard_memory, dashboard_overview, OverviewResponse, MemoryResponse }


def StatusPill(text: str, tone: str = "info") -> JsxElement {
    return <span className={"status-pill " + tone}>{text}</span>;
}


def SectionCard(title: str, subtitle: str, body: JsxElement) -> JsxElement {
    return <section className="card pad">
        <div className="card-header">
            <div>
                <h2>{title}</h2>
                <p className="brand-subtitle">{subtitle}</p>
            </div>
        </div>
        {body}
    </section>;
}


def StatCard(title: str, value: str, meta: str, tone: str = "info") -> JsxElement {
    return <section className="card pad">
        <StatusPill text={title} tone={tone}/>
        <div className="stat-card-value">{value}</div>
        <div className="stat-card-meta">{meta}</div>
    </section>;
}


def OverviewContent(overview: OverviewResponse) -> JsxElement {
    update_text = "Stable";
    update_tone = "good";
    if overview.update_available {
        update_text = "Update available";
        update_tone = "warn";
    }

    return <div className="stack">
        <div className="page-header">
            <div>
                <h1>Control Room</h1>
                <p>Monitor runtime health, update state, channels, sessions, and persisted data from one place.</p>
            </div>
            <div className="header-actions">
                <StatusPill text={update_text} tone={update_tone}/>
                <StatusPill text={overview.version} tone="info"/>
            </div>
        </div>

        <div className="stats-grid">
            <StatCard title="Memory" value={str(overview.memory_count)} meta="Live persisted memories" tone="info"/>
            <StatCard title="Sessions" value={str(overview.session_count)} meta="Tracked chat sessions" tone="good"/>
            <StatCard title="Skills" value={str(overview.skill_count)} meta={str(overview.native_skill_count) + " native · " + str(overview.workflow_skill_count) + " workflow"} tone="warn"/>
            <StatCard title="Provider" value={overview.default_provider} meta={overview.default_model} tone="info"/>
        </div>

        <div className="layout-grid">
            <div className="stack">
                <SectionCard title="Runtime & Update" subtitle="Current workspace and update status" body={
                    <div className="list-grid">
                        <div className="notice">
                            Workspace: {overview.workspace}<br/>
                            Current commit: {overview.current_commit}<br/>
                            Latest main: {overview.latest_commit}
                        </div>
                    </div>
                }/>
                <SectionCard title="Identity Core" subtitle="Seeded assistant state available before the first conversation" body={
                    <div className="list-grid">
                        <div className="list-item"><div className="list-item-title">Name</div><div className="list-item-meta">{overview.assistant_name}</div></div>
                        <div className="list-item"><div className="list-item-title">Identity</div><div className="list-item-meta">{overview.assistant_identity}</div></div>
                        <div className="list-item"><div className="list-item-title">Soul</div><div className="list-item-meta">{overview.assistant_soul}</div></div>
                        <div className="list-item"><div className="list-item-title">Root graph</div><div className="list-item-meta">{overview.root_ready and "ready" or "missing"}</div></div>
                    </div>
                }/>
            </div>
            <div className="stack">
                <SectionCard title="Configuration Snapshot" subtitle="Read-only first version" body={
                    <div className="list-grid">
                        <div className="list-item"><div className="list-item-title">Assistant name</div><div className="list-item-meta">{overview.assistant_name}</div></div>
                        <div className="list-item"><div className="list-item-title">Default provider</div><div className="list-item-meta">{overview.default_provider}</div></div>
                        <div className="list-item"><div className="list-item-title">Default model</div><div className="list-item-meta">{overview.default_model}</div></div>
                        <div className="list-item"><div className="list-item-title">Dream maintenance</div><div className="list-item-meta">{overview.dream_enabled and "enabled" or "disabled"} · every {str(overview.dream_interval_hours)}h</div></div>
                    </div>
                }/>
                <SectionCard title="Skills Snapshot" subtitle="Installed skills visible to the runtime" body={
                    <div className="list-grid">
                        {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in overview.skill_labels]}
                    </div>
                }/>
            </div>
        </div>
    </div>;
}


def SessionsContent(overview: OverviewResponse) -> JsxElement {
    return <div className="stack">
        <div className="page-header">
            <div>
                <h1>Sessions</h1>
                <p>Review recent conversations and turn counts, similar to the OpenClaw control UI's session-first admin workflow.</p>
            </div>
            <div className="header-actions">
                <StatusPill text={str(overview.session_count) + " tracked"} tone="good"/>
                <StatusPill text={overview.default_provider} tone="info"/>
            </div>
        </div>
        <div className="layout-grid">
            <SectionCard title="Recent Sessions" subtitle="Latest stored conversations" body={
                <div className="list-grid">
                    {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in overview.recent_session_labels]}
                </div>
            }/>
            <SectionCard title="Runtime Snapshot" subtitle="Current workspace, model, and maintenance cadence" body={
                <div className="list-grid">
                    <div className="list-item"><div className="list-item-title">Workspace</div><div className="list-item-meta">{overview.workspace}</div></div>
                    <div className="list-item"><div className="list-item-title">Default model</div><div className="list-item-meta">{overview.default_model}</div></div>
                    <div className="list-item"><div className="list-item-title">Dream maintenance</div><div className="list-item-meta">{overview.dream_enabled and "enabled" or "disabled"} · every {str(overview.dream_interval_hours)}h</div></div>
                </div>
            }/>
        </div>
    </div>;
}


def ChannelsContent(overview: OverviewResponse) -> JsxElement {
    return <div className="stack">
        <div className="page-header">
            <div>
                <h1>Channels & Config</h1>
                <p>Keep operational settings and channel state grouped together, following OpenClaw's control-surface structure.</p>
            </div>
            <div className="header-actions">
                <StatusPill text={overview.default_provider} tone="info"/>
                <StatusPill text={overview.update_available and "Update available" or "Stable"} tone={overview.update_available and "warn" or "good"}/>
            </div>
        </div>
        <div className="layout-grid">
            <SectionCard title="Channel Status" subtitle="Enabled and disabled communication surfaces" body={
                <div className="list-grid">
                    {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in overview.channel_summary]}
                </div>
            }/>
            <div className="stack">
                <SectionCard title="Configuration Snapshot" subtitle="Read-only provider and assistant settings" body={
                    <div className="list-grid">
                        <div className="list-item"><div className="list-item-title">Assistant name</div><div className="list-item-meta">{overview.assistant_name}</div></div>
                        <div className="list-item"><div className="list-item-title">Default provider</div><div className="list-item-meta">{overview.default_provider}</div></div>
                        <div className="list-item"><div className="list-item-title">Default model</div><div className="list-item-meta">{overview.default_model}</div></div>
                    </div>
                }/>
                <SectionCard title="Identity Snapshot" subtitle="Core personality and root-memory status" body={
                    <div className="list-grid">
                        <div className="list-item"><div className="list-item-title">Identity</div><div className="list-item-meta">{overview.assistant_identity}</div></div>
                        <div className="list-item"><div className="list-item-title">Soul</div><div className="list-item-meta">{overview.assistant_soul}</div></div>
                        <div className="list-item"><div className="list-item-title">Root graph</div><div className="list-item-meta">{overview.root_ready and "ready" or "missing"}</div></div>
                    </div>
                }/>
            </div>
        </div>
    </div>;
}


def SkillsContent(overview: OverviewResponse) -> JsxElement {
    return <div className="stack">
        <div className="page-header">
            <div>
                <h1>Skills</h1>
                <p>Track workspace, shared, bundled, and managed skills with the same operator-first emphasis OpenClaw gives to tool and skill visibility.</p>
            </div>
            <div className="header-actions">
                <StatusPill text={str(overview.skill_count) + " total"} tone="warn"/>
                <StatusPill text={str(overview.workflow_skill_count) + " workflow"} tone="info"/>
            </div>
        </div>
        <div className="stats-grid">
            <StatCard title="Native" value={str(overview.native_skill_count)} meta="Typed Python/native skills" tone="good"/>
            <StatCard title="Workflow" value={str(overview.workflow_skill_count)} meta="SKILL.md / OpenClaw-style skills" tone="warn"/>
            <StatCard title="Workspace" value={str(overview.workspace_skill_count)} meta="Repo-local skills" tone="info"/>
            <StatCard title="Managed" value={str(overview.managed_skill_count)} meta="ClawHub or git-tracked" tone="info"/>
        </div>
        <div className="layout-grid">
            <SectionCard title="Skill Sources" subtitle="Current installation distribution" body={
                <div className="list-grid">
                    <div className="list-item"><div className="list-item-title">Bundled</div><div className="list-item-meta">{str(overview.bundled_skill_count)}</div></div>
                    <div className="list-item"><div className="list-item-title">Workspace</div><div className="list-item-meta">{str(overview.workspace_skill_count)}</div></div>
                    <div className="list-item"><div className="list-item-title">Shared</div><div className="list-item-meta">{str(overview.shared_skill_count)}</div></div>
                    <div className="list-item"><div className="list-item-title">Managed</div><div className="list-item-meta">{str(overview.managed_skill_count)}</div></div>
                </div>
            }/>
            <SectionCard title="Inventory" subtitle="Resolved skill view using the latest runtime precedence" body={
                <div className="list-grid">
                    {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in overview.skill_inventory_labels]}
                </div>
            }/>
        </div>
    </div>;
}


def GraphView(memory: MemoryResponse, onRefresh: any) -> JsxElement {
    return <div className="graph-shell">
        <div className="graph-toolbar">
            <button className="graph-refresh" onClick={onRefresh}>Refresh graph</button>
        </div>
        <div className="graph-canvas">
            <GraphMemoryCanvas memory={memory}/>
        </div>
        <div className="graph-legend">
            <div className="list-item"><div className="list-item-title">Root node</div><div className="list-item-meta">Pinned assistant origin for the graph cluster</div></div>
            <div className="list-item"><div className="list-item-title">Core identity</div><div className="list-item-meta">Name, identity, soul, dream cadence, and other foundational nodes</div></div>
            <div className="list-item"><div className="list-item-title">Conversation graph</div><div className="list-item-meta">Movable sessions, turns, and memory nodes connected through live relationships</div></div>
        </div>
    </div>;
}


def MemoryContent(memory: MemoryResponse) -> JsxElement {
    return <div className="stack">
        <div className="page-header">
            <div>
                <h1>Graph Memory</h1>
                <p>Inspect the knowledge graph directly: rooted identity nodes, session branches, and memory relationships visualized as a live graph instead of a flat card list.</p>
            </div>
            <div className="header-actions">
                <StatusPill text={str(memory.node_count) + " nodes"} tone="info"/>
                <StatusPill text={str(memory.edge_count) + " edges"} tone="good"/>
            </div>
        </div>
        <div className="memory-grid">
            <SectionCard title="Knowledge Graph" subtitle="Jac-style node-link view of the current memory graph" body={
                <GraphView memory={memory} onRefresh={lambda -> None { memory = await dashboard_memory(); }}/>
            }/>
            <div className="stack">
                <SectionCard title="Core Identity Graph" subtitle="Seeded root graph available before conversations begin" body={
                    <div className="list-grid">
                        {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in memory.core_node_labels]}
                        <div className="list-item"><div className="list-item-title">Core edges</div><div className="list-item-meta">{str(memory.core_edge_count)}</div></div>
                    </div>
                }/>
                <SectionCard title="Node Details" subtitle="Exact node payloads driving the graph view" body={
                    <div className="node-grid">
                        {[<div key={node.id} className="node-card">
                            <div className="node-kind">{node.kind}</div>
                            <div className="node-title">{node.label}</div>
                            <div className="list-item-meta">{node.system_key != "" and node.system_key or "ad-hoc node"}</div>
                            <div className="list-item-meta">{len(node.topics) > 0 and "Topics: " + ", ".join(node.topics) or "No topics yet"}</div>
                        </div> for node in memory.nodes[:18]]}
                    </div>
                }/>
                <SectionCard title="Relationship Feed" subtitle="Derived from persisted memory edges" body={
                    <div className="edge-list">
                        {[<div key={edge.source + "-" + edge.target + "-" + edge.label} className="edge-item">
                            <strong>{edge.label}</strong>
                            <div className="list-item-meta">{edge.source} → {edge.target}</div>
                        </div> for edge in memory.edges[:50]]}
                    </div>
                }/>
                <SectionCard title="Profile State" subtitle="Persisted identity and assistant preferences" body={<pre className="textarea">{memory.profile_json}</pre>}/>
            </div>
        </div>
    </div>;
}


def:pub DashboardApp() -> JsxElement {
    has page: str = "overview";
    has overview: OverviewResponse | None = None;
    has memory: MemoryResponse | None = None;
    has loading: bool = True;
    has error: str = "";

    async def load_data() {
        loading = True;
        error = "";
        try {
            overview = await dashboard_overview();
            memory = await dashboard_memory();
        } except Exception as e {
            error = f"Dashboard failed to load: {e}";
        }
        loading = False;
    }

    async can with entry {
        await load_data();
    }


    overview_nav_class = "nav-link";
    sessions_nav_class = "nav-link";
    channels_nav_class = "nav-link";
    skills_nav_class = "nav-link";
    memory_nav_class = "nav-link";
    if page == "overview" {
        overview_nav_class = "nav-link active";
    }
    if page == "sessions" {
        sessions_nav_class = "nav-link active";
    }
    if page == "channels" {
        channels_nav_class = "nav-link active";
    }
    if page == "skills" {
        skills_nav_class = "nav-link active";
    }
    if page == "memory" {
        memory_nav_class = "nav-link active";
    }

    body = <div className="notice">Loading Graphclaw Control UI…</div>;
    if error {
        body = <div className="notice">{error}</div>;
    } elif not loading and overview != None and memory != None {
        if page == "memory" {
            body = <MemoryContent memory={memory}/>;
        } elif page == "sessions" {
            body = <SessionsContent overview={overview}/>;
        } elif page == "channels" {
            body = <ChannelsContent overview={overview}/>;
        } elif page == "skills" {
            body = <SkillsContent overview={overview}/>;
        } else {
            body = <OverviewContent overview={overview}/>;
        }
    }

    return <div className="dashboard-shell">
        <aside className="sidebar">
            <div className="brand-pill">Graphclaw Control UI</div>
            <h1 className="brand-title">Graphclaw</h1>
            <p className="brand-subtitle">A Jac-native control surface for runtime status, sessions, channels, and graph memory.</p>
            <div className="sidebar-nav">
                <button className={overview_nav_class} onClick={lambda -> None { page = "overview"; }}>
                    <span className="nav-title">Overview</span>
                    <span className="nav-meta">Runtime, updates, provider, skills</span>
                </button>
                <button className={sessions_nav_class} onClick={lambda -> None { page = "sessions"; }}>
                    <span className="nav-title">Sessions</span>
                    <span className="nav-meta">Recent chats and turn history summary</span>
                </button>
                <button className={channels_nav_class} onClick={lambda -> None { page = "channels"; }}>
                    <span className="nav-title">Channels</span>
                    <span className="nav-meta">Channel status and config snapshot</span>
                </button>
                <button className={skills_nav_class} onClick={lambda -> None { page = "skills"; }}>
                    <span className="nav-title">Skills</span>
                    <span className="nav-meta">Workspace, bundled, and managed skills</span>
                </button>
                <button className={memory_nav_class} onClick={lambda -> None { page = "memory"; }}>
                    <span className="nav-title">Graph Memory</span>
                    <span className="nav-meta">Nodes, edges, profile state, session graph</span>
                </button>
            </div>
            <div className="sidebar-footer">
                <div className="list-item-title">Admin Surface</div>
                <div className="list-item-meta">Built in Jac with a live view over Graphclaw runtime state.</div>
            </div>
        </aside>
        <main className="main">{body}</main>
    </div>;
}
