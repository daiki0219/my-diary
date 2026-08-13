import {
  decodeExchangeEntryCursor,
  decodeExchangeTopCursor,
  isExchangeTopView,
  type ExchangeEntryCursor,
  type ExchangeEntryMode,
  type ExchangeTopCursor,
  type ExchangeTopView,
} from "@/lib/exchange-cursor";

export type ExchangeSearchParams = Record<
  string,
  string | string[] | undefined
>;

export type ExchangeTopQuery = {
  view: ExchangeTopView;
  cursor: ExchangeTopCursor | null;
};

export type ExchangeEntryQuery = {
  mode: ExchangeEntryMode;
  cursor: ExchangeEntryCursor | null;
};

function hasOnlyKeys(
  searchParams: ExchangeSearchParams,
  allowedKeys: readonly string[],
) {
  return Object.keys(searchParams).every((key) => allowedKeys.includes(key));
}

function readOptionalSingleValue(value: string | string[] | undefined) {
  if (value === undefined) {
    return { valid: true, value: null } as const;
  }

  if (typeof value !== "string" || value.length === 0) {
    return { valid: false, value: null } as const;
  }

  return { valid: true, value } as const;
}

export function parseExchangeTopQuery(
  searchParams: ExchangeSearchParams,
): ExchangeTopQuery | null {
  if (!hasOnlyKeys(searchParams, ["view", "cursor"])) {
    return null;
  }

  const rawView = readOptionalSingleValue(searchParams.view);
  const rawCursor = readOptionalSingleValue(searchParams.cursor);

  if (!rawView.valid || !rawCursor.valid) {
    return null;
  }

  const view = rawView.value ?? "active";

  if (!isExchangeTopView(view)) {
    return null;
  }

  const cursor = rawCursor.value
    ? decodeExchangeTopCursor(rawCursor.value, view)
    : null;

  if (rawCursor.value && !cursor) {
    return null;
  }

  return { view, cursor };
}

export function parseExchangeEntryQuery(
  searchParams: ExchangeSearchParams,
  diaryId: string,
): ExchangeEntryQuery | null {
  if (!hasOnlyKeys(searchParams, ["view", "cursor"])) {
    return null;
  }

  const rawView = readOptionalSingleValue(searchParams.view);
  const rawCursor = readOptionalSingleValue(searchParams.cursor);

  if (!rawView.valid || !rawCursor.valid) {
    return null;
  }

  const mode = rawView.value ?? "oldest";

  if (mode !== "oldest" && mode !== "latest") {
    return null;
  }

  const cursor = rawCursor.value
    ? decodeExchangeEntryCursor(rawCursor.value, diaryId, mode)
    : null;

  if (rawCursor.value && !cursor) {
    return null;
  }

  return { mode, cursor };
}

export function buildExchangeTopQuery(view: ExchangeTopView, cursor?: string) {
  const searchParams = new URLSearchParams({ view });

  if (cursor) {
    searchParams.set("cursor", cursor);
  }

  return searchParams.toString();
}

export function buildExchangeEntryQuery(
  mode: ExchangeEntryMode,
  cursor?: string,
) {
  const searchParams = new URLSearchParams();

  if (mode === "latest") {
    searchParams.set("view", "latest");
  }

  if (cursor) {
    searchParams.set("cursor", cursor);
  }

  return searchParams.toString();
}
