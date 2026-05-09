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

  return {
    ok: true,
    inputKind,
    unixSeconds: Math.floor(date.getTime() / 1000),
    unixMilliseconds: date.getTime(),
    iso: date.toISOString(),
    local: new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "medium",
      timeZone: timezone
    }).format(date),
    timezone
  };
}
