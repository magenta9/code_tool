import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import { useMemo, useState } from "react";
import { toolCatalog, type ToolCatalogEntry } from "@codetool/shared";
import {
  AudioLines,
  Braces,
  Clock3,
  Cloud,
  GitCompare,
  Image,
  Images,
  KeyRound,
  MessagesSquare,
  Music,
  Search,
  Settings,
  Activity,
  Wrench
} from "lucide-react";

const icons = {
  AudioLines,
  Braces,
  Clock3,
  Cloud,
  GitCompare,
  Image,
  Images,
  KeyRound,
  MessagesSquare,
  Music
};

export function Workbench(): JSX.Element {
  const [query, setQuery] = useState("");
  const navigate = useNavigate();
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
    <div className="grid h-screen grid-cols-[292px_minmax(0,1fr)] grid-rows-[var(--app-titlebar-height)_minmax(0,1fr)] bg-[var(--app-bg)] text-[var(--app-text)]">
      <div className="app-drag-region col-span-2 flex h-[var(--app-titlebar-height)] items-center justify-between border-b border-[var(--app-border)] bg-[linear-gradient(180deg,rgba(255,255,255,0.035),rgba(255,255,255,0.01))] px-5 text-[var(--app-text-dim)] backdrop-blur-md">
        <div className="w-[var(--app-traffic-light-safe-width)] shrink-0" />
        <div className="flex-1" />
        <div className="rounded-full border border-white/6 bg-white/[0.03] px-3 py-1 text-[10px] font-medium uppercase tracking-[0.24em] text-[#868e86]">
          CodeTool
        </div>
      </div>
      <aside className="app-no-drag flex min-h-0 flex-col border-r border-[var(--app-border)] bg-[linear-gradient(180deg,#0d1113_0%,#090c0d_100%)]">
        <div className="px-4 pb-4 pt-5">
          <div className="rounded-[22px] border border-white/[0.05] bg-white/[0.025] p-4 shadow-[0_18px_48px_rgba(0,0,0,0.24),inset_0_1px_0_rgba(255,255,255,0.04)]">
            <div className="flex items-center gap-3">
              <div className="grid h-11 w-11 place-items-center rounded-[14px] bg-[linear-gradient(180deg,#e7ff94_0%,#d8ff63_100%)] text-[#11140d] shadow-[0_12px_32px_rgba(216,255,99,0.24)]">
                <Wrench size={18} />
              </div>
              <div className="min-w-0">
                <div className="text-[15px] font-semibold tracking-[-0.02em] text-[#f4f7f1]">CodeTool</div>
                <div className="mt-1 text-[11px] text-[var(--app-text-muted)]">Electron workbench</div>
              </div>
            </div>
          </div>
        </div>
        <label className="app-no-drag mx-4 mb-4 flex h-11 items-center gap-3 rounded-[14px] border border-white/[0.06] bg-white/[0.045] px-3.5 text-[var(--app-text-muted)] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition-[background-color,border-color] duration-150 focus-within:border-white/[0.1] focus-within:bg-white/[0.06]">
          <Search size={15} />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search tools"
            className="app-no-drag min-w-0 flex-1 bg-transparent text-[13px] text-[var(--app-text)] outline-none placeholder:text-[#747c74]"
          />
        </label>
        <nav className="min-h-0 flex-1 space-y-6 overflow-y-auto px-4 pb-5">
          <ToolGroup title="Dev Tools" tools={filtered.filter((tool) => tool.category === "devTools")} />
          <ToolGroup title="AI Tools" tools={filtered.filter((tool) => tool.category === "aiTools")} />
        </nav>
        <div className="grid grid-cols-2 gap-2 border-t border-[var(--app-border)] p-4 pt-3">
          <button
            type="button"
            onClick={() => navigate("/settings")}
            className="app-no-drag flex h-11 items-center justify-center gap-2 rounded-[14px] border border-white/[0.06] bg-white/[0.045] text-[12px] font-medium text-[#d6ddd3] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition-[background-color,transform,border-color] duration-150 active:scale-[0.98] [@media(hover:hover)]:hover:border-white/[0.1] [@media(hover:hover)]:hover:bg-white/[0.065]"
          >
            <Settings size={14} /> Settings
          </button>
          <button
            type="button"
            onClick={() => navigate("/diagnostics")}
            className="app-no-drag flex h-11 items-center justify-center gap-2 rounded-[14px] border border-white/[0.06] bg-white/[0.045] text-[12px] font-medium text-[#d6ddd3] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition-[background-color,transform,border-color] duration-150 active:scale-[0.98] [@media(hover:hover)]:hover:border-white/[0.1] [@media(hover:hover)]:hover:bg-white/[0.065]"
          >
            <Activity size={14} /> Logs
          </button>
        </div>
      </aside>
      <main className="app-no-drag flex min-h-0 flex-col overflow-hidden bg-[radial-gradient(circle_at_top_right,rgba(216,255,99,0.07),transparent_24%),linear-gradient(180deg,#080a0b_0%,#060708_100%)]">
        <div className="min-h-0 flex-1 overflow-y-auto px-7 py-7">
          <div className="mb-6 flex flex-wrap items-center gap-3">
            <span className="rounded-full border border-white/8 bg-white/[0.04] px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.22em] text-[var(--app-text-muted)]">
              {activeGroupLabel}
            </span>
            <div className="h-px w-6 bg-white/8" />
            <span className="text-[13px] text-[var(--app-text-dim)]">{active.title}</span>
          </div>
          <Outlet />
        </div>
      </main>
    </div>
  );
}

function ToolGroup({ title, tools }: { title: string; tools: readonly ToolCatalogEntry[] }): JSX.Element {
  if (tools.length === 0) {
    return (
      <section>
        <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.16em] text-[#727a72]">{title}</h2>
        <div className="px-2 text-[12px] text-[#666d66]">No matches</div>
      </section>
    );
  }
  return (
    <section>
      <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.16em] text-[#727a72]">{title}</h2>
      <div className="space-y-2">
        {tools.map((tool) => {
          const Icon = icons[tool.icon as keyof typeof icons];
          return (
            <NavLink
              key={tool.id}
              to={tool.routePath}
              className={({ isActive }) =>
                [
                  "app-no-drag group flex min-h-14 items-start gap-3 rounded-[16px] px-3 py-3 transition-[background-color,box-shadow,transform,color] duration-150 active:scale-[0.985]",
                  isActive
                    ? "bg-[linear-gradient(180deg,rgba(255,255,255,0.085),rgba(255,255,255,0.04))] text-[#f4f7f1] shadow-[0_18px_48px_rgba(0,0,0,0.24),inset_0_1px_0_rgba(255,255,255,0.04)]"
                    : "text-[#c9d0c8] [@media(hover:hover)]:hover:bg-white/[0.045] [@media(hover:hover)]:hover:text-[#f3f6ef]"
                ].join(" ")
              }
            >
              {({ isActive }) => (
                <>
                  <span
                    className={[
                      "mt-0.5 grid h-9 w-9 shrink-0 place-items-center rounded-[12px] transition-[background-color,color,box-shadow] duration-150",
                      isActive
                        ? "bg-[linear-gradient(180deg,#e7ff94_0%,#d8ff63_100%)] text-[#12150c] shadow-[0_10px_24px_rgba(216,255,99,0.18)]"
                        : "bg-white/[0.045] text-[#95a096] [@media(hover:hover)]:group-hover:bg-white/[0.065] [@media(hover:hover)]:group-hover:text-[#dbe2d7]"
                    ].join(" ")}
                  >
                    <Icon size={16} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[13px] font-medium tracking-[-0.01em]">{tool.title}</span>
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
