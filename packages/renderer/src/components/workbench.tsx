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
  const filtered = useMemo(
    () =>
      toolCatalog.filter((tool) => {
        const haystack = `${tool.title} ${tool.description} ${tool.category}`.toLowerCase();
        return haystack.includes(query.trim().toLowerCase());
      }),
    [query]
  );

  return (
    <div className="grid h-screen grid-cols-[280px_minmax(0,1fr)] bg-[#08090a] text-[#e8ece7]">
      <aside className="flex min-h-0 flex-col border-r border-white/8 bg-[#0d0f10]">
        <div className="flex h-14 items-center gap-3 px-4">
          <div className="grid h-8 w-8 place-items-center rounded-[8px] bg-[#d1ff4a] text-[#11140d] shadow-[0_0_24px_rgba(209,255,74,0.22)]">
            <Wrench size={17} />
          </div>
          <div>
            <div className="text-[15px] font-semibold tracking-[-0.012em] text-[#f2f5ef]">CodeTool</div>
            <div className="text-[11px] text-[#7d847d]">Electron workbench</div>
          </div>
        </div>
        <label className="mx-3 mb-3 flex h-10 items-center gap-2 rounded-[8px] bg-white/[0.045] px-3 text-[#8b928b] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.05)]">
          <Search size={15} />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search tools"
            className="min-w-0 flex-1 bg-transparent text-[13px] text-[#e8ece7] outline-none placeholder:text-[#747b74]"
          />
        </label>
        <nav className="min-h-0 flex-1 space-y-5 overflow-y-auto px-3 pb-4">
          <ToolGroup title="Dev Tools" tools={filtered.filter((tool) => tool.category === "devTools")} />
          <ToolGroup title="AI Tools" tools={filtered.filter((tool) => tool.category === "aiTools")} />
        </nav>
        <div className="grid grid-cols-2 gap-2 border-t border-white/8 p-3">
          <button
            type="button"
            onClick={() => navigate("/settings")}
            className="flex h-10 items-center justify-center gap-2 rounded-[8px] bg-white/[0.045] text-[12px] text-[#cbd1c8] transition-transform duration-150 active:scale-95"
          >
            <Settings size={14} /> Settings
          </button>
          <button
            type="button"
            onClick={() => navigate("/diagnostics")}
            className="flex h-10 items-center justify-center gap-2 rounded-[8px] bg-white/[0.045] text-[12px] text-[#cbd1c8] transition-transform duration-150 active:scale-95"
          >
            <Activity size={14} /> Logs
          </button>
        </div>
      </aside>
      <main className="min-h-0 overflow-hidden bg-[#08090a]">
        <header className="flex h-14 items-center justify-between border-b border-white/8 px-6">
          <div>
            <div className="text-[13px] text-[#858c85]">Current tool</div>
            <h1 className="text-[17px] font-semibold tracking-[-0.012em] text-[#f2f5ef]">{active.title}</h1>
          </div>
          <div className="flex items-center gap-2 text-[12px] text-[#a5ada3]">
            <span className="rounded-[8px] bg-[#d1ff4a]/12 px-2.5 py-1 text-[#d1ff4a]">local-first</span>
            <span className="rounded-[8px] bg-white/[0.045] px-2.5 py-1">macOS</span>
          </div>
        </header>
        <div className="h-[calc(100vh-56px)] overflow-y-auto px-6 py-5">
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
        <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.12em] text-[#6f776f]">{title}</h2>
        <div className="px-2 text-[12px] text-[#666d66]">No matches</div>
      </section>
    );
  }
  return (
    <section>
      <h2 className="px-2 pb-2 text-[11px] font-medium uppercase tracking-[0.12em] text-[#6f776f]">{title}</h2>
      <div className="space-y-1">
        {tools.map((tool) => {
          const Icon = icons[tool.icon as keyof typeof icons];
          return (
            <NavLink
              key={tool.id}
              to={tool.routePath}
              className={({ isActive }) =>
                [
                  "flex min-h-12 items-center gap-3 rounded-[8px] px-3 py-2 transition-[background-color,transform] duration-150 active:scale-95",
                  isActive ? "bg-[#d1ff4a] text-[#11140d]" : "text-[#c9d0c8] [@media(hover:hover)]:hover:bg-white/[0.055]"
                ].join(" ")
              }
            >
              <Icon size={17} />
              <span className="min-w-0">
                <span className="block truncate text-[13px] font-medium">{tool.title}</span>
                <span className="block truncate text-[11px] opacity-70">{tool.description}</span>
              </span>
            </NavLink>
          );
        })}
      </div>
    </section>
  );
}
