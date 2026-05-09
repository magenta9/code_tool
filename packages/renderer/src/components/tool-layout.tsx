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
    <section className="mx-auto grid max-w-[1180px] gap-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="max-w-4xl">
          <h2 className="text-[28px] font-semibold leading-[1.08] tracking-[-0.03em] text-[var(--app-text)]">{title}</h2>
          <p className="mt-2 text-[14px] leading-6 text-[var(--app-text-muted)]">{description}</p>
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </div>
      {children}
    </section>
  );
}

export function Panel({
  title,
  children,
  actions,
  className = ""
}: {
  title: string;
  children: ReactNode;
  actions?: ReactNode;
  className?: string;
}): JSX.Element {
  return (
    <div
      className={`rounded-[24px] border border-[var(--app-border)] bg-[linear-gradient(180deg,rgba(255,255,255,0.04),rgba(255,255,255,0.018))] p-4 shadow-[0_18px_52px_rgba(0,0,0,0.2),inset_0_1px_0_rgba(255,255,255,0.04)] ${className}`}
    >
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="h-2 w-2 rounded-full bg-[var(--app-accent)] shadow-[0_0_18px_rgba(124,150,255,0.6)]" />
          <div className="text-[11px] font-semibold uppercase tracking-[0.22em] text-[var(--app-text-muted)]">{title}</div>
        </div>
        {actions}
      </div>
      {children}
    </div>
  );
}

export function TextArea(props: JSX.IntrinsicElements["textarea"]): JSX.Element {
  return (
    <textarea
      {...props}
      className={[
        "min-h-72 w-full rounded-[18px] border border-white/[0.06] bg-[linear-gradient(180deg,#0b1017_0%,#0f1520_100%)] px-4 py-4 font-mono text-[13px] leading-6 text-[var(--app-text)] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] outline-none transition-[border-color,box-shadow,background-color] duration-150 placeholder:text-[#657183] focus:border-[var(--app-accent-soft-strong)] focus:shadow-[0_0_0_4px_rgba(124,150,255,0.09),inset_0_1px_0_rgba(255,255,255,0.06)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function TextInput(props: JSX.IntrinsicElements["input"]): JSX.Element {
  return (
    <input
      {...props}
      className={[
        "h-11 w-full rounded-[14px] border border-white/[0.06] bg-[linear-gradient(180deg,#0b1017_0%,#0f1520_100%)] px-3.5 text-[13px] text-[var(--app-text)] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] outline-none transition-[border-color,box-shadow,background-color] duration-150 placeholder:text-[#657183] focus:border-[var(--app-accent-soft-strong)] focus:shadow-[0_0_0_4px_rgba(124,150,255,0.09),inset_0_1px_0_rgba(255,255,255,0.06)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function SelectField(props: JSX.IntrinsicElements["select"]): JSX.Element {
  return (
    <select
      {...props}
      className={[
        "h-11 w-full rounded-[14px] border border-white/[0.06] bg-[linear-gradient(180deg,#0b1017_0%,#0f1520_100%)] px-3.5 text-[13px] text-[var(--app-text)] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] outline-none transition-[border-color,box-shadow,background-color] duration-150 focus:border-[var(--app-accent-soft-strong)] focus:shadow-[0_0_0_4px_rgba(124,150,255,0.09),inset_0_1px_0_rgba(255,255,255,0.06)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function CodeBlock({ children, className = "" }: { children: ReactNode; className?: string }): JSX.Element {
  return (
    <pre
      className={`whitespace-pre-wrap rounded-[18px] border border-white/[0.06] bg-[linear-gradient(180deg,#0b1017_0%,#0f1520_100%)] px-4 py-3.5 font-mono text-[13px] leading-6 text-[#dce2d9] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] ${className}`}
    >
      {children}
    </pre>
  );
}

export function PillTag({
  children,
  icon,
  tone = "neutral",
  className = ""
}: {
  children: ReactNode;
  icon?: ReactNode;
  tone?: "neutral" | "accent" | "success" | "warning" | "danger";
  className?: string;
}): JSX.Element {
  const toneClass = {
    neutral: "border-white/[0.08] bg-white/[0.045] text-[var(--app-text-muted)]",
    accent: "border-[var(--app-accent-soft-strong)] bg-[var(--app-accent-soft)] text-[#dbe5ff]",
    success: "border-[rgba(89,193,142,0.25)] bg-[rgba(89,193,142,0.12)] text-[#b8f0d0]",
    warning: "border-[rgba(245,194,107,0.24)] bg-[rgba(245,194,107,0.12)] text-[#f6dda5]",
    danger: "border-[rgba(255,125,145,0.24)] bg-[rgba(255,125,145,0.12)] text-[#ffc2cb]"
  }[tone];

  return (
    <span className={`inline-flex h-7 items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium tracking-[0.01em] ${toneClass} ${className}`}>
      {icon}
      <span>{children}</span>
    </span>
  );
}

export function PrimaryButton(props: JSX.IntrinsicElements["button"]): JSX.Element {
  return (
    <button
      {...props}
      className={[
        "inline-flex h-10 items-center justify-center gap-2 rounded-[14px] bg-[linear-gradient(180deg,#8ca7ff_0%,#6f8eff_100%)] px-4 text-[13px] font-semibold text-[var(--app-accent-ink)] shadow-[0_12px_28px_rgba(124,150,255,0.24),inset_0_1px_0_rgba(255,255,255,0.24)] transition-[transform,box-shadow,opacity] duration-150 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:-translate-y-px [@media(hover:hover)]:hover:shadow-[0_16px_32px_rgba(124,150,255,0.28),inset_0_1px_0_rgba(255,255,255,0.28)]",
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
        "inline-flex h-10 items-center justify-center gap-2 rounded-[14px] border border-white/[0.06] bg-white/[0.045] px-4 text-[13px] font-medium text-[#dde4ef] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition-[background-color,border-color,transform] duration-150 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:border-white/[0.12] [@media(hover:hover)]:hover:bg-white/[0.075]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function StatusStrip({ children }: { children: ReactNode }): JSX.Element {
  return (
    <div className="rounded-[16px] border border-[var(--app-accent-soft-strong)] bg-[var(--app-accent-soft)] px-3.5 py-2.5 text-[12px] leading-5 text-[#dce5ff] shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]">
      {children}
    </div>
  );
}
