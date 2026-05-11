export interface TimestampConversionInput {
  value: string;
  timezone?: string;
}

export interface TimestampConversionResult {
  ok: boolean;
  inputKind?: "seconds" | "milliseconds" | "date";
  unixSeconds?: number;
  unixMilliseconds?: number;
  iso?: string;
  rfc3339?: string;
  rfc2822?: string;
  rfc7231?: string;
  utc?: string;
  local?: string;
  timezone: string;
  error?: string;
}

export function convertTimestamp(input: TimestampConversionInput): TimestampConversionResult {
  const timezone = input.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  const trimmed = input.value.trim();
  if (!trimmed) {
    return { ok: false, timezone, error: "Enter a timestamp or date." };
  }

  const numeric = Number(trimmed);
  let date: Date;
  let inputKind: TimestampConversionResult["inputKind"];

  if (Number.isFinite(numeric) && /^-?\d+(\.\d+)?$/.test(trimmed)) {
    inputKind = Math.abs(numeric) < 10_000_000_000 ? "seconds" : "milliseconds";
    date = new Date(inputKind === "seconds" ? numeric * 1000 : numeric);
  } else {
    inputKind = "date";
    date = new Date(trimmed);
  }

  if (Number.isNaN(date.getTime())) {
    return { ok: false, timezone, error: "Invalid timestamp or date." };
  }

  let local: string;
  try {
    local = new Intl.DateTimeFormat(undefined, {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      timeZone: timezone,
      timeZoneName: "short"
    }).format(date);
  } catch {
    return { ok: false, timezone, error: `Invalid timezone: ${timezone}` };
  }

  const iso = date.toISOString();

  return {
    ok: true,
    inputKind,
    unixSeconds: Math.floor(date.getTime() / 1000),
    unixMilliseconds: date.getTime(),
    iso,
    rfc3339: iso,
    rfc2822: formatRfc2822(date),
    rfc7231: date.toUTCString(),
    utc: date.toUTCString(),
    local,
    timezone
  };
}

function formatRfc2822(date: Date): string {
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${weekdays[date.getUTCDay()]}, ${pad(date.getUTCDate())} ${months[date.getUTCMonth()]} ${date.getUTCFullYear()} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())} +0000`;
}

function pad(value: number): string {
  return String(value).padStart(2, "0");
}
