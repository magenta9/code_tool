import { Link } from "react-router-dom";
import { toolCatalog } from "@codetool/shared";

export function Home(): JSX.Element {
  return (
    <section className="mx-auto grid max-w-7xl gap-5">
      <div className="rounded-[8px] bg-white/[0.035] p-5 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.06)]">
        <h2 className="text-[24px] font-semibold tracking-[-0.012em] text-[#f3f6f0]">CodeTool workbench</h2>
        <p className="mt-2 max-w-3xl text-[13px] leading-5 text-[#8c948b]">
          Ten local-first utilities are available from the rail. DevTools run through typed IPC; AI tools use MiniMax task events,
          history, assets, and diagnostics without exposing secrets to the renderer.
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {toolCatalog.map((tool) => (
          <Link
            key={tool.id}
            to={tool.routePath}
            className="min-h-28 rounded-[8px] bg-white/[0.035] p-4 text-[#e8ece7] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.06)] transition-[background-color,transform] duration-150 active:scale-95 [@media(hover:hover)]:hover:bg-white/[0.055]"
          >
            <div className="flex items-center justify-between gap-3">
              <h3 className="text-[15px] font-semibold tracking-[-0.012em]">{tool.title}</h3>
              <span className="rounded-[8px] bg-white/[0.06] px-2 py-1 text-[11px] text-[#a8b0a6]">
                {tool.category === "aiTools" ? "AI" : "Dev"}
              </span>
            </div>
            <p className="mt-2 text-[12px] leading-5 text-[#8c948b]">{tool.description}</p>
          </Link>
        ))}
      </div>
    </section>
  );
}
