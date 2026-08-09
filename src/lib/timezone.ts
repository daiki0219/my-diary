const FALLBACK_TIME_ZONES = ["UTC"] as const;

function createBaseTimeZoneOptions() {
  return Array.from(
    new Set([
      ...Intl.supportedValuesOf("timeZone"),
      ...FALLBACK_TIME_ZONES,
    ]),
  ).sort();
}

const baseTimeZoneOptions = createBaseTimeZoneOptions();
const baseTimeZoneOptionSet = new Set(baseTimeZoneOptions);

export function isRuntimeTimeZone(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value !== value.trim()
  ) {
    return false;
  }

  try {
    new Intl.DateTimeFormat("en", { timeZone: value }).format(0);
    return true;
  } catch {
    return false;
  }
}

export function getTimeZoneOptions(currentTimeZone?: string) {
  if (
    !currentTimeZone ||
    baseTimeZoneOptionSet.has(currentTimeZone) ||
    !isRuntimeTimeZone(currentTimeZone)
  ) {
    return [...baseTimeZoneOptions];
  }

  return [...baseTimeZoneOptions, currentTimeZone].sort();
}

export function isSelectableTimeZone(
  value: unknown,
  currentTimeZone?: string,
) {
  return (
    typeof value === "string" &&
    getTimeZoneOptions(currentTimeZone).includes(value)
  );
}
