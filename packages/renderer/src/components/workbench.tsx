import { NavLink, Outlet } from "react-router-dom";
import { useMemo, useState } from "react";
import { toolCatalog, type ToolCatalogEntry } from "@codetool/shared";
import {
  AudioLines,
  Bot,
  Braces,
  Clock3,
  Cloud,
  GitCompare,
  Image,
  Images,
  KanbanSquare,
  KeyRound,
  MessagesSquare,
  Music,
  Search,
  Settings,
  Activity
} from "lucide-react";
import { SearchField } from "./tool-layout";

const icons = {
  AudioLines,
  Bot,
  Braces,
  Clock3,
  Cloud,
  GitCompare,
  Image,
  Images,
  KanbanSquare,
  KeyRound,
  MessagesSquare,
  Music
};

const utilityEntries = [
  { routePath: "/settings", title: "Settings", description: "Credentials and data import", icon: Settings },
  { routePath: "/diagnostics", title: "Logs", description: "Local diagnostics output", icon: Activity }
] as const;

export function Workbench(): JSX.Element {
  const [query, setQuery] = useState("");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const filtered = useMemo(
    () =>
      toolCatalog.filter((tool) => {
        const haystack = `${tool.title} ${tool.description} ${tool.category}`.toLowerCase();
        return haystack.includes(query.trim().toLowerCase());
      }),
    [query]
  );

  return (
    <div
      className={`grid h-screen grid-rows-[var(--app-titlebar-height)_minmax(0,1fr)] bg-[var(--app-bg)] text-[var(--app-text)] ${sidebarCollapsed ? "grid-cols-[68px_minmax(0,1fr)]" : "grid-cols-[276px_minmax(0,1fr)]"}`}
    >
      <div className="app-drag-region col-span-2 flex h-[var(--app-titlebar-height)] items-center justify-between border-b border-[var(--app-border)] bg-[rgba(255,255,255,0.88)] px-5 text-[var(--app-text-dim)] backdrop-blur-md">
        <div className="w-[var(--app-traffic-light-safe-width)] shrink-0" />
        <div className="flex-1" />
        <div className="rounded-full border border-[var(--app-border)] bg-[var(--app-panel)] px-3 py-1 text-[10px] font-medium uppercase tracking-[0.18em] text-[var(--app-text-muted)]">
          Workspace
        </div>
      </div>
      <aside className="app-no-drag flex min-h-0 flex-col border-r border-[var(--app-border)] bg-[var(--app-sidebar)]">
        <div className={sidebarCollapsed ? "px-3 pb-4 pt-5" : "px-5 pb-4 pt-5"}>
          <div className={sidebarCollapsed ? "flex flex-col items-center gap-3" : "flex items-center gap-3"}>
            <button
              type="button"
              className="grid h-10 w-10 place-items-center overflow-hidden rounded-[8px] text-[var(--app-accent)] transition-transform active:scale-[0.98]"
              aria-label={sidebarCollapsed ? "Open toolbar" : "Collapse toolbar"}
              onClick={() => setSidebarCollapsed((current) => !current)}
            >
              <img src="./codetool-icon.svg" alt="" className="h-full w-full" />
            </button>
            <div className={sidebarCollapsed ? "hidden" : "min-w-0"}>
              <div className="text-[15px] font-semibold tracking-normal text-[var(--app-text)]">CodeTool</div>
              <div className="mt-1 text-[11px] text-[var(--app-text-muted)]">Local workbench</div>
            </div>
          </div>
        </div>
        {sidebarCollapsed ? null : (
          <SearchField
            icon={<Search size={15} />}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search tools"
            className="app-no-drag mx-4 mb-4 self-stretch bg-[var(--ui-surface-quiet)]"
            inputClassName="app-no-drag flex-1"
          />
        )}
        <nav className={`min-h-0 flex-1 space-y-6 overflow-y-auto pb-5 ${sidebarCollapsed ? "px-2" : "px-4"}`}>
          <ToolGroup title="Dev Tools" tools={filtered.filter((tool) => tool.category === "devTools")} collapsed={sidebarCollapsed} />
          <ToolGroup title="AI Tools" tools={filtered.filter((tool) => tool.category === "aiTools")} collapsed={sidebarCollapsed} />
          <UtilityGroup collapsed={sidebarCollapsed} />
        </nav>
      </aside>
      <main className="app-no-drag flex min-h-0 flex-col overflow-hidden bg-[var(--app-bg)]">
        <div className="min-h-0 flex-1 overflow-y-auto px-7 py-7">
          <Outlet />
        </div>
      </main>
    </div>
  );
}

function UtilityGroup({ collapsed }: { collapsed: boolean }): JSX.Element {
  return (
    <section>
      {collapsed ? null : <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-dim)]">Utilities</h2>}
      <div className="space-y-2">
        {utilityEntries.map((utility) => {
          const Icon = utility.icon;
          return (
            <NavLink
              key={utility.routePath}
              to={utility.routePath}
              aria-label={utility.title}
              className={({ isActive }) =>
                [
                  "app-no-drag group flex min-h-12 items-start rounded-[8px] border border-transparent transition-[background-color,color,border-color] duration-150",
                  collapsed ? "justify-center px-2 py-2" : "gap-3 px-3 py-2.5",
                  isActive
                    ? "border-[var(--ui-border)] bg-[rgba(25,25,22,0.055)] text-[var(--ui-text)]"
                    : "text-[var(--ui-text-muted)] [@media(hover:hover)]:hover:border-[var(--ui-border)] [@media(hover:hover)]:hover:bg-[rgba(25,25,22,0.045)] [@media(hover:hover)]:hover:text-[var(--ui-text)]"
                ].join(" ")
              }
            >
              {({ isActive }) => (
                <>
                  <span
                    className={[
                      "mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-[8px] transition-[background-color,color,box-shadow] duration-150",
                      isActive
                        ? "bg-[var(--ui-primary-soft)] text-[var(--ui-primary)]"
                        : "bg-transparent text-[var(--ui-text-muted)] [@media(hover:hover)]:group-hover:text-[var(--ui-text)]"
                    ].join(" ")}
                  >
                    <Icon size={15} />
                  </span>
                  <span className={collapsed ? "hidden" : "min-w-0 flex-1"}>
                    <span className="block truncate text-[13px] font-medium tracking-normal">{utility.title}</span>
                    <span className="mt-0.5 block truncate text-[11px] leading-4 opacity-65">{utility.description}</span>
                  </span>
                </>
              )}
            </NavLink>
          );
        })}
      </div>
    </section>
  );
}

function ToolGroup({ title, tools, collapsed }: { title: string; tools: readonly ToolCatalogEntry[]; collapsed: boolean }): JSX.Element {
  if (tools.length === 0) {
    return (
      <section>
        {collapsed ? null : <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-dim)]">{title}</h2>}
        {collapsed ? null : <div className="px-2 text-[12px] text-[var(--app-text-dim)]">No matches</div>}
      </section>
    );
  }
  return (
    <section>
      {collapsed ? null : <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-dim)]">{title}</h2>}
      <div className="space-y-2">
        {tools.map((tool) => {
          const Icon = icons[tool.icon as keyof typeof icons];
          return (
            <NavLink
              key={tool.id}
              to={tool.routePath}
              aria-label={tool.title}
              className={({ isActive }) =>
                [
                  "app-no-drag group flex min-h-14 items-start rounded-[8px] border border-transparent transition-[background-color,color,border-color] duration-150",
                  collapsed ? "justify-center px-2 py-2" : "gap-3 px-3 py-3",
                  isActive
                    ? "border-[var(--ui-border)] bg-[rgba(25,25,22,0.055)] text-[var(--ui-text)]"
                    : "text-[var(--ui-text-muted)] [@media(hover:hover)]:hover:border-[var(--ui-border)] [@media(hover:hover)]:hover:bg-[rgba(25,25,22,0.045)] [@media(hover:hover)]:hover:text-[var(--ui-text)]"
                ].join(" ")
              }
            >
              {({ isActive }) => (
                <>
                  <span
                    className={[
                      "mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-[8px] transition-[background-color,color,box-shadow] duration-150",
                      isActive
                        ? "bg-[var(--ui-primary-soft)] text-[var(--ui-primary)]"
                        : "bg-transparent text-[var(--ui-text-muted)] [@media(hover:hover)]:group-hover:text-[var(--ui-text)]"
                    ].join(" ")}
                  >
                    <Icon size={16} />
                  </span>
                  <span className={collapsed ? "hidden" : "min-w-0 flex-1"}>
                    <span className="block truncate text-[13px] font-medium tracking-normal">{tool.title}</span>
                    <span className="mt-1 block truncate text-[11px] leading-4 opacity-65">{tool.description}</span>
                  </span>
                </>
              )}
            </NavLink>
          );
        })}
      </div>
    </section>
  );
}
