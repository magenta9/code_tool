import type { ReactNode } from "react";

export function ToolLayout({
  title,
  description,
  actions,
  children
}: {
  title: string;
  description: string;
  actions?: ReactNode;
  children: ReactNode;
}): JSX.Element {
  return (
    <section className="mx-auto grid max-w-7xl gap-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-[24px] font-semibold leading-tight tracking-[-0.012em] text-[#f3f6f0]">{title}</h2>
          <p className="mt-1 max-w-3xl text-[13px] leading-5 text-[#8c948b]">{description}</p>
        </div>
        {actions}
      </div>
      {children}
    </section>
  );
}

export function Panel({
  title,
  children,
  className = ""
}: {
  title: string;
  children: ReactNode;
  className?: string;
}): JSX.Element {
  return (
    <div className={`rounded-[8px] bg-white/[0.035] p-3 shadow-[inset_0_0_0_1px_rgba(255,255,255,0.06)] ${className}`}>
      <div className="mb-2 text-[12px] font-medium uppercase tracking-[0.12em] text-[#7b847a]">{title}</div>
      {children}
    </div>
  );
}

export function TextArea(props: JSX.IntrinsicElements["textarea"]): JSX.Element {
  return (
    <textarea
      {...props}
      className={[
        "min-h-64 w-full rounded-[8px] bg-[#050607] p-3 font-mono text-[13px] leading-5 text-[#e8ece7] shadow-[inset_0_0_0_1px_rgba(255,255,255,0.08)] outline-none transition-[box-shadow] duration-150 placeholder:text-[#5e665e] focus:shadow-[inset_0_0_0_1px_rgba(209,255,74,0.55)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function PrimaryButton(props: JSX.IntrinsicElements["button"]): JSX.Element {
  return (
    <button
      {...props}
      className={[
        "inline-flex h-10 items-center justify-center gap-2 rounded-[8px] bg-[#d1ff4a] px-4 text-[13px] font-semibold text-[#11140d] transition-[opacity,transform] duration-150 active:scale-95 disabled:cursor-not-allowed disabled:opacity-45",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function SecondaryButton(props: JSX.IntrinsicElements["button"]): JSX.Element {
  return (
    <button
      {...props}
      className={[
        "inline-flex h-10 items-center justify-center gap-2 rounded-[8px] bg-white/[0.06] px-4 text-[13px] font-medium text-[#dce2d9] transition-[background-color,transform] duration-150 active:scale-95 disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:bg-white/[0.09]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function StatusStrip({ children }: { children: ReactNode }): JSX.Element {
  return (
    <div className="rounded-[8px] bg-[#d1ff4a]/10 px-3 py-2 text-[12px] leading-5 text-[#d8ff72] shadow-[inset_0_0_0_1px_rgba(209,255,74,0.16)]">
      {children}
    </div>
  );
}
