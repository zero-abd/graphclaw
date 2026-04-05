import "../dashboard.css";
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
            <StatCard title="Skills" value={str(overview.skill_count)} meta="Installed runtime skills" tone="warn"/>
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
                        {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in overview.channel_summary]}
                    </div>
                }/>
                <SectionCard title="Recent Sessions" subtitle="Latest stored conversations" body={
                    <div className="list-grid">
                        {[<div key={label} className="list-item"><div className="list-item-title">{label}</div></div> for label in overview.recent_session_labels]}
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


def MemoryContent(memory: MemoryResponse) -> JsxElement {
    return <div className="stack">
        <div className="page-header">
            <div>
                <h1>Graph Memory</h1>
                <p>Inspect persisted profile, memory nodes, sessions, and relationships from the current Graphclaw workspace.</p>
            </div>
            <div className="header-actions">
                <StatusPill text={str(memory.node_count) + " nodes"} tone="info"/>
                <StatusPill text={str(memory.edge_count) + " edges"} tone="good"/>
            </div>
        </div>
        <div className="memory-grid">
            <SectionCard title="Node Explorer" subtitle="Profile, memories, sessions, and turns" body={
                <div className="node-grid">
                    {[<div key={node.id} className="node-card">
                        <div className="node-kind">{node.kind}</div>
                        <div className="node-title">{node.label}</div>
                        <div className="list-item-meta">ID: {node.id}</div>
                    </div> for node in memory.nodes[:40]]}
                </div>
            }/>
            <div className="stack">
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


def:pub app() -> JsxElement {
    has page: str = "overview";
    has overview: OverviewResponse = OverviewResponse();
    has memory: MemoryResponse = MemoryResponse();
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
    memory_nav_class = "nav-link";
    if page == "overview" {
        overview_nav_class = "nav-link active";
    }
    if page == "memory" {
        memory_nav_class = "nav-link active";
    }

    body = <div className="notice">Loading Graphclaw Control UI…</div>;
    if error {
        body = <div className="notice">{error}</div>;
    } elif not loading {
        if page == "memory" {
            body = <MemoryContent memory={memory}/>;
        } else {
            body = <OverviewContent overview={overview}/>;
        }
    }

    return <div className="dashboard-shell">
        <aside className="sidebar">
            <div className="brand-pill">Graphclaw Control</div>
            <h1 className="brand-title">{overview.assistant_name}</h1>
            <p className="brand-subtitle">A polished Jac-built admin dashboard for runtime visibility, state inspection, and graph memory browsing.</p>
            <div className="sidebar-nav">
                <button className={overview_nav_class} onClick={lambda -> None { page = "overview"; }}>
                    <span className="nav-title">Overview</span>
                    <span className="nav-meta">Runtime, config, sessions, channels, updates</span>
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
