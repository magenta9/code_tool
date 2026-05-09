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
    <section className="mx-auto grid max-w-[1180px] gap-5">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div className="max-w-4xl">
          <h2 className="text-[26px] font-semibold leading-[1.12] tracking-normal text-[var(--app-text)]">{title}</h2>
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
      className={`rounded-[12px] border border-[var(--app-border)] bg-[var(--app-panel)] p-4 shadow-[0_12px_34px_rgba(24,24,22,0.05)] ${className}`}
    >
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="h-2 w-2 rounded-full bg-[var(--app-accent)]" />
          <div className="text-[11px] font-semibold uppercase tracking-[0.14em] text-[var(--app-text-muted)]">{title}</div>
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
        "min-h-72 w-full rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] px-4 py-4 font-mono text-[13px] leading-6 text-[var(--app-text)] outline-none transition-[border-color,box-shadow,background-color] duration-150 placeholder:text-[var(--app-text-dim)] focus:border-[var(--app-border-strong)] focus:shadow-[0_0_0_4px_rgba(36,36,36,0.06)]",
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
        "h-10 w-full rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] px-3.5 text-[13px] text-[var(--app-text)] outline-none transition-[border-color,box-shadow,background-color] duration-150 placeholder:text-[var(--app-text-dim)] focus:border-[var(--app-border-strong)] focus:shadow-[0_0_0_4px_rgba(36,36,36,0.06)]",
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
        "h-10 w-full rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] px-3.5 text-[13px] text-[var(--app-text)] outline-none transition-[border-color,box-shadow,background-color] duration-150 focus:border-[var(--app-border-strong)] focus:shadow-[0_0_0_4px_rgba(36,36,36,0.06)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function CodeBlock({ children, className = "" }: { children: ReactNode; className?: string }): JSX.Element {
  return (
    <pre
      className={`whitespace-pre-wrap rounded-[8px] border border-[var(--app-border)] bg-[var(--app-code-bg)] px-4 py-3.5 font-mono text-[13px] leading-6 text-[var(--app-text)] ${className}`}
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
    neutral: "border-[var(--app-border)] bg-[var(--app-bg-muted)] text-[var(--app-text-muted)]",
    accent: "border-[var(--app-border-strong)] bg-[var(--app-accent-soft)] text-[var(--app-text)]",
    success: "border-[rgba(32,180,134,0.22)] bg-[rgba(32,180,134,0.1)] text-[#157b61]",
    warning: "border-[rgba(230,160,46,0.22)] bg-[rgba(230,160,46,0.12)] text-[#94610f]",
    danger: "border-[rgba(194,65,45,0.22)] bg-[rgba(194,65,45,0.1)] text-[#a73424]"
  }[tone];

  return (
    <span className={`inline-flex h-7 items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium tracking-normal ${toneClass} ${className}`}>
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
        "inline-flex h-9 items-center justify-center gap-2 rounded-[8px] bg-[var(--app-accent)] px-4 text-[13px] font-semibold text-[var(--app-accent-ink)] shadow-[0_6px_16px_rgba(24,24,22,0.12)] transition-[transform,box-shadow,opacity] duration-150 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:-translate-y-px [@media(hover:hover)]:hover:shadow-[0_8px_20px_rgba(24,24,22,0.16)]",
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
        "inline-flex h-9 items-center justify-center gap-2 rounded-[8px] border border-[var(--app-border)] bg-[var(--app-panel)] px-4 text-[13px] font-medium text-[var(--app-text)] transition-[background-color,border-color,transform] duration-150 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:border-[var(--app-border-strong)] [@media(hover:hover)]:hover:bg-[var(--app-panel-strong)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function StatusStrip({ children }: { children: ReactNode }): JSX.Element {
  return (
    <div className="rounded-[8px] border border-[var(--app-border-strong)] bg-[var(--app-accent-soft)] px-3.5 py-2.5 text-[12px] leading-5 text-[var(--app-text)]">
      {children}
    </div>
  );
}
