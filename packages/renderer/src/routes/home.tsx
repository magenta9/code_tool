import { Link } from "react-router-dom";
import { toolCatalog } from "@codetool/shared";

export function Home(): JSX.Element {
  return (
    <section className="mx-auto grid max-w-7xl gap-5">
      <div className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] p-5 shadow-[0_12px_34px_rgba(24,24,22,0.05)]">
        <h2 className="text-[24px] font-semibold tracking-normal text-[var(--app-text)]">CodeTool workbench</h2>
        <p className="mt-2 max-w-3xl text-[13px] leading-5 text-[var(--app-text-muted)]">
          Local-first utilities are available from the rail. DevTools run through typed IPC; AI tools use MiniMax task events,
          history, assets, and diagnostics without exposing secrets to the renderer.
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {toolCatalog.map((tool) => (
          <Link
            key={tool.id}
            to={tool.routePath}
            className="min-h-28 rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] p-4 text-[var(--app-text)] shadow-[0_10px_28px_rgba(24,24,22,0.04)] transition-[background-color,border-color,transform] duration-150 active:scale-95 [@media(hover:hover)]:hover:border-[var(--app-border-strong)] [@media(hover:hover)]:hover:bg-[var(--app-panel-strong)]"
          >
            <div className="flex items-center justify-between gap-3">
              <h3 className="text-[15px] font-semibold tracking-normal">{tool.title}</h3>
              <span className="rounded-[8px] border border-[var(--app-border)] bg-[var(--app-bg-muted)] px-2 py-1 text-[11px] text-[var(--app-text-muted)]">
                {tool.category === "aiTools" ? "AI" : "Dev"}
              </span>
            </div>
            <p className="mt-2 text-[12px] leading-5 text-[var(--app-text-muted)]">{tool.description}</p>
          </Link>
        ))}
      </div>
    </section>
  );
}
