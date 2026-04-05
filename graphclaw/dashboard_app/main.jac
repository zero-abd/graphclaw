cl import from .app { DashboardApp }

import from graphclaw.dashboard {
    DashboardSaveResponse,
    MemoryResponse,
    OverviewResponse,
    dashboard_memory,
    dashboard_overview,
    dashboard_save_settings,
}

cl {
    def:pub app() -> JsxElement {
        return <DashboardApp/>;
    }
}
