import { Link } from "react-router-dom";
import { toolCatalog } from "@codetool/shared";

export function Home(): JSX.Element {
  return (
    <section className="mx-auto grid max-w-7xl gap-5">
      <div className="rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)] p-5 shadow-[0_1px_2px_rgba(24,24,22,0.035)]">
        <h2 className="text-[22px] font-semibold tracking-normal text-[var(--ui-text)]">CodeTool workbench</h2>
        <p className="mt-2 max-w-3xl text-[13px] leading-5 text-[var(--ui-text-muted)]">
          Local-first utilities are available from the rail. DevTools run through typed IPC; AI tools use MiniMax task events,
          history, assets, and diagnostics without exposing secrets to the renderer.
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {toolCatalog.map((tool) => (
          <Link
            key={tool.id}
            to={tool.routePath}
            className="min-h-28 rounded-[8px] border border-[var(--ui-border)] bg-[var(--ui-surface)] p-4 text-[var(--ui-text)] shadow-[0_1px_2px_rgba(24,24,22,0.03)] transition-[background-color,border-color] duration-150 [@media(hover:hover)]:hover:border-[var(--ui-border-strong)] [@media(hover:hover)]:hover:bg-[var(--ui-surface-quiet)]"
          >
            <div className="flex items-center justify-between gap-3">
              <h3 className="text-[15px] font-semibold tracking-normal">{tool.title}</h3>
              <span className="rounded-[7px] border border-[var(--ui-border)] bg-[var(--ui-surface-soft)] px-2 py-1 text-[11px] text-[var(--ui-text-muted)]">
                {tool.category === "aiTools" ? "AI" : "Dev"}
              </span>
            </div>
            <p className="mt-2 text-[12px] leading-5 text-[var(--ui-text-muted)]">{tool.description}</p>
          </Link>
        ))}
      </div>
    </section>
  );
}
