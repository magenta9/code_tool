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
          <h2 className="text-[30px] font-semibold leading-[1.05] tracking-[-0.03em] text-[#f4f7f1]">{title}</h2>
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
      className={`rounded-[20px] border border-[var(--app-border)] bg-[linear-gradient(180deg,rgba(255,255,255,0.045),rgba(255,255,255,0.02))] p-4 shadow-[0_28px_80px_rgba(0,0,0,0.28),inset_0_1px_0_rgba(255,255,255,0.04)] ${className}`}
    >
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="h-2 w-2 rounded-full bg-[var(--app-accent)] shadow-[0_0_18px_rgba(216,255,99,0.55)]" />
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
        "min-h-72 w-full rounded-[16px] border border-white/[0.06] bg-[linear-gradient(180deg,#06090a_0%,#090d0f_100%)] px-4 py-4 font-mono text-[13px] leading-6 text-[#edf1ea] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] outline-none transition-[border-color,box-shadow,background-color] duration-150 placeholder:text-[#59635d] focus:border-[rgba(216,255,99,0.24)] focus:shadow-[0_0_0_4px_rgba(216,255,99,0.08),inset_0_1px_0_rgba(255,255,255,0.06)]",
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
        "h-11 w-full rounded-[14px] border border-white/[0.06] bg-[linear-gradient(180deg,#06090a_0%,#090d0f_100%)] px-3.5 text-[13px] text-[#edf1ea] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] outline-none transition-[border-color,box-shadow,background-color] duration-150 placeholder:text-[#59635d] focus:border-[rgba(216,255,99,0.24)] focus:shadow-[0_0_0_4px_rgba(216,255,99,0.08),inset_0_1px_0_rgba(255,255,255,0.06)]",
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
        "h-11 w-full rounded-[14px] border border-white/[0.06] bg-[linear-gradient(180deg,#06090a_0%,#090d0f_100%)] px-3.5 text-[13px] text-[#edf1ea] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] outline-none transition-[border-color,box-shadow,background-color] duration-150 focus:border-[rgba(216,255,99,0.24)] focus:shadow-[0_0_0_4px_rgba(216,255,99,0.08),inset_0_1px_0_rgba(255,255,255,0.06)]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function CodeBlock({ children, className = "" }: { children: ReactNode; className?: string }): JSX.Element {
  return (
    <pre
      className={`whitespace-pre-wrap rounded-[16px] border border-white/[0.06] bg-[linear-gradient(180deg,#06090a_0%,#090d0f_100%)] px-4 py-3.5 font-mono text-[13px] leading-6 text-[#dce2d9] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] ${className}`}
    >
      {children}
    </pre>
  );
}

export function PrimaryButton(props: JSX.IntrinsicElements["button"]): JSX.Element {
  return (
    <button
      {...props}
      className={[
        "inline-flex h-10 items-center justify-center gap-2 rounded-[12px] bg-[linear-gradient(180deg,#e7ff94_0%,#d8ff63_100%)] px-4 text-[13px] font-semibold text-[var(--app-accent-ink)] shadow-[0_12px_28px_rgba(216,255,99,0.18),inset_0_1px_0_rgba(255,255,255,0.32)] transition-[transform,box-shadow,opacity] duration-150 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:-translate-y-px [@media(hover:hover)]:hover:shadow-[0_16px_32px_rgba(216,255,99,0.22),inset_0_1px_0_rgba(255,255,255,0.34)]",
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
        "inline-flex h-10 items-center justify-center gap-2 rounded-[12px] border border-white/[0.06] bg-white/[0.05] px-4 text-[13px] font-medium text-[#dce2d9] shadow-[inset_0_1px_0_rgba(255,255,255,0.04)] transition-[background-color,border-color,transform] duration-150 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 [@media(hover:hover)]:hover:border-white/[0.11] [@media(hover:hover)]:hover:bg-white/[0.08]",
        props.className ?? ""
      ].join(" ")}
    />
  );
}

export function StatusStrip({ children }: { children: ReactNode }): JSX.Element {
  return (
    <div className="rounded-[14px] border border-[rgba(216,255,99,0.14)] bg-[rgba(216,255,99,0.08)] px-3.5 py-2.5 text-[12px] leading-5 text-[#dff88d] shadow-[inset_0_1px_0_rgba(255,255,255,0.03)]">
      {children}
    </div>
  );
}
