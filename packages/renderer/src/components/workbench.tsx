import { NavLink, Outlet, useLocation } from "react-router-dom";
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

export function Workbench(): JSX.Element {
  const [query, setQuery] = useState("");
  const location = useLocation();
  const active = toolCatalog.find((tool) => location.pathname === tool.routePath) ?? toolCatalog[0];
  const activeGroupLabel = active.category === "aiTools" ? "AI Tools" : "Dev Tools";
  const filtered = useMemo(
    () =>
      toolCatalog.filter((tool) => {
        const haystack = `${tool.title} ${tool.description} ${tool.category}`.toLowerCase();
        return haystack.includes(query.trim().toLowerCase());
      }),
    [query]
  );

  return (
    <div className="grid h-screen grid-cols-[276px_minmax(0,1fr)] grid-rows-[var(--app-titlebar-height)_minmax(0,1fr)] bg-[var(--app-bg)] text-[var(--app-text)]">
      <div className="app-drag-region col-span-2 flex h-[var(--app-titlebar-height)] items-center justify-between border-b border-[var(--app-border)] bg-[rgba(255,255,255,0.88)] px-5 text-[var(--app-text-dim)] backdrop-blur-md">
        <div className="w-[var(--app-traffic-light-safe-width)] shrink-0" />
        <div className="flex-1" />
        <div className="rounded-full border border-[var(--app-border)] bg-[var(--app-panel)] px-3 py-1 text-[10px] font-medium uppercase tracking-[0.18em] text-[var(--app-text-muted)]">
          Workspace
        </div>
      </div>
      <aside className="app-no-drag flex min-h-0 flex-col border-r border-[var(--app-border)] bg-[var(--app-sidebar)]">
        <div className="px-5 pb-4 pt-5">
          <div className="flex items-center gap-3">
            <div className="grid h-10 w-10 place-items-center overflow-hidden rounded-[8px] text-[var(--app-accent)]">
              <img src="./codetool-icon.svg" alt="" className="h-full w-full" />
            </div>
            <div className="min-w-0">
              <div className="text-[15px] font-semibold tracking-normal text-[var(--app-text)]">CodeTool</div>
              <div className="mt-1 text-[11px] text-[var(--app-text-muted)]">Local workbench</div>
            </div>
          </div>
        </div>
        <label className="app-no-drag mx-4 mb-4 flex h-10 items-center gap-3 rounded-[8px] bg-[rgba(36,36,36,0.045)] px-3.5 text-[var(--app-text-muted)] transition-[background-color,box-shadow] duration-150 focus-within:bg-[rgba(36,36,36,0.065)] focus-within:shadow-[0_0_0_3px_rgba(36,36,36,0.045)]">
          <Search size={15} />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search tools"
            className="app-no-drag min-w-0 flex-1 bg-transparent text-[13px] text-[var(--app-text)] outline-none placeholder:text-[var(--app-text-dim)]"
          />
        </label>
        <nav className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pb-5">
          <ToolGroup title="Dev Tools" tools={filtered.filter((tool) => tool.category === "devTools")} />
          <ToolGroup title="AI Tools" tools={filtered.filter((tool) => tool.category === "aiTools")} />
          <UtilityGroup />
        </nav>
      </aside>
      <main className="app-no-drag flex min-h-0 flex-col overflow-hidden bg-[var(--app-bg)]">
        <div className="min-h-0 flex-1 overflow-y-auto px-7 py-7">
          <div className="mb-6 flex flex-wrap items-center gap-3">
            <span className="rounded-full border border-[var(--app-border-strong)] bg-[var(--app-accent-soft)] px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.16em] text-[var(--app-text)]">
              {activeGroupLabel}
            </span>
            <div className="h-px w-6 bg-[var(--app-border)]" />
            <span className="text-[13px] text-[var(--app-text-dim)]">{active.title}</span>
          </div>
          <Outlet />
        </div>
      </main>
    </div>
  );
}

function UtilityGroup(): JSX.Element {
  const utilities = [
    { routePath: "/settings", title: "Settings", description: "Credentials and data import", icon: Settings },
    { routePath: "/diagnostics", title: "Logs", description: "Local diagnostics output", icon: Activity }
  ];

  return (
    <section>
      <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-dim)]">Utilities</h2>
      <div className="space-y-2">
        {utilities.map((utility) => {
          const Icon = utility.icon;
          return (
            <NavLink
              key={utility.routePath}
              to={utility.routePath}
              className={({ isActive }) =>
                [
                  "app-no-drag group flex min-h-12 items-start gap-3 rounded-[8px] border-l-2 border-transparent px-3 py-2.5 transition-[background-color,transform,color,border-color] duration-150 active:scale-[0.985]",
                  isActive
                    ? "border-l-[var(--app-accent)] bg-transparent text-[var(--app-text)]"
                    : "text-[var(--app-text-muted)] [@media(hover:hover)]:hover:bg-[rgba(36,36,36,0.045)] [@media(hover:hover)]:hover:text-[var(--app-text)]"
                ].join(" ")
              }
            >
              {({ isActive }) => (
                <>
                  <span
                    className={[
                      "mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-[8px] transition-[background-color,color,box-shadow] duration-150",
                      isActive
                        ? "bg-transparent text-[var(--app-accent)]"
                        : "bg-transparent text-[var(--app-text-muted)] [@media(hover:hover)]:group-hover:text-[var(--app-text)]"
                    ].join(" ")}
                  >
                    <Icon size={15} />
                  </span>
                  <span className="min-w-0 flex-1">
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

function ToolGroup({ title, tools }: { title: string; tools: readonly ToolCatalogEntry[] }): JSX.Element {
  if (tools.length === 0) {
    return (
      <section>
        <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-dim)]">{title}</h2>
        <div className="px-2 text-[12px] text-[var(--app-text-dim)]">No matches</div>
      </section>
    );
  }
  return (
    <section>
      <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.14em] text-[var(--app-text-dim)]">{title}</h2>
      <div className="space-y-2">
        {tools.map((tool) => {
          const Icon = icons[tool.icon as keyof typeof icons];
          return (
            <NavLink
              key={tool.id}
              to={tool.routePath}
              className={({ isActive }) =>
                [
                  "app-no-drag group flex min-h-14 items-start gap-3 rounded-[8px] border-l-2 border-transparent px-3 py-3 transition-[background-color,transform,color,border-color] duration-150 active:scale-[0.985]",
                  isActive
                    ? "border-l-[var(--app-accent)] bg-transparent text-[var(--app-text)]"
                    : "text-[var(--app-text-muted)] [@media(hover:hover)]:hover:bg-[rgba(36,36,36,0.045)] [@media(hover:hover)]:hover:text-[var(--app-text)]"
                ].join(" ")
              }
            >
              {({ isActive }) => (
                <>
                  <span
                    className={[
                      "mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-[8px] transition-[background-color,color,box-shadow] duration-150",
                      isActive
                        ? "bg-transparent text-[var(--app-accent)]"
                        : "bg-transparent text-[var(--app-text-muted)] [@media(hover:hover)]:group-hover:text-[var(--app-text)]"
                    ].join(" ")}
                  >
                    <Icon size={16} />
                  </span>
                  <span className="min-w-0 flex-1">
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
