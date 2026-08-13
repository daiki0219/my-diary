import { isUuid } from "@/lib/profile-data";
import { isPostSearchTimestamp } from "@/lib/search-cursor";

const CURSOR_VERSION = 1;
const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;
const LOWERCASE_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

export const EXCHANGE_TOP_VIEWS = [
  "active",
  "invitations",
  "archived",
] as const;

export type ExchangeTopView = (typeof EXCHANGE_TOP_VIEWS)[number];
export type ExchangeEntryMode = "oldest" | "latest";
export type ExchangeEntryCursorDirection = "after" | "before";

export type ExchangeTopCursor = {
  v: 1;
  view: ExchangeTopView;
  createdAt: string;
  id: string;
};

export type ExchangeEntryCursor = {
  v: 1;
  diaryId: string;
  mode: ExchangeEntryMode;
  direction: ExchangeEntryCursorDirection;
  createdAt: string;
  entryId: string;
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function decodeOpaqueCursor(value: string): unknown | null {
  if (
    value.length === 0 ||
    value.length > CURSOR_MAX_LENGTH ||
    !CURSOR_CHARACTER_PATTERN.test(value)
  ) {
    return null;
  }

  try {
    const bytes = Buffer.from(value, "base64url");

    if (bytes.toString("base64url") !== value) {
      return null;
    }

    const json = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return JSON.parse(json) as unknown;
  } catch {
    return null;
  }
}

export function canonicalizeExchangeUuid(value: string) {
  return isUuid(value) ? value.toLowerCase() : null;
}

export function isExchangeTopView(value: string): value is ExchangeTopView {
  return EXCHANGE_TOP_VIEWS.some((view) => view === value);
}

export function encodeExchangeTopCursor({
  view,
  createdAt,
  id,
}: Omit<ExchangeTopCursor, "v">) {
  const canonicalId = canonicalizeExchangeUuid(id);

  if (!isExchangeTopView(view) || !isPostSearchTimestamp(createdAt) || !canonicalId) {
    throw new Error("Cannot encode an invalid Exchange list cursor.");
  }

  return Buffer.from(
    JSON.stringify({ v: CURSOR_VERSION, view, createdAt, id: canonicalId }),
    "utf8",
  ).toString("base64url");
}

export function decodeExchangeTopCursor(
  value: string,
  expectedView: ExchangeTopView,
): ExchangeTopCursor | null {
  const cursor = decodeOpaqueCursor(value);

  if (
    typeof cursor !== "object" ||
    cursor === null ||
    !hasExactKeys(cursor, ["v", "view", "createdAt", "id"]) ||
    !("v" in cursor) ||
    !("view" in cursor) ||
    !("createdAt" in cursor) ||
    !("id" in cursor) ||
    cursor.v !== CURSOR_VERSION ||
    typeof cursor.view !== "string" ||
    !isExchangeTopView(cursor.view) ||
    cursor.view !== expectedView ||
    typeof cursor.createdAt !== "string" ||
    !isPostSearchTimestamp(cursor.createdAt) ||
    typeof cursor.id !== "string" ||
    !LOWERCASE_UUID_PATTERN.test(cursor.id)
  ) {
    return null;
  }

  return {
    v: CURSOR_VERSION,
    view: cursor.view,
    createdAt: cursor.createdAt,
    id: cursor.id,
  };
}

function getEntryCursorDirection(mode: ExchangeEntryMode) {
  return mode === "oldest" ? "after" : "before";
}

export function encodeExchangeEntryCursor({
  diaryId,
  mode,
  direction,
  createdAt,
  entryId,
}: Omit<ExchangeEntryCursor, "v">) {
  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);
  const canonicalEntryId = canonicalizeExchangeUuid(entryId);

  if (
    !canonicalDiaryId ||
    !canonicalEntryId ||
    (mode !== "oldest" && mode !== "latest") ||
    direction !== getEntryCursorDirection(mode) ||
    !isPostSearchTimestamp(createdAt)
  ) {
    throw new Error("Cannot encode an invalid Exchange entry cursor.");
  }

  return Buffer.from(
    JSON.stringify({
      v: CURSOR_VERSION,
      diaryId: canonicalDiaryId,
      mode,
      direction,
      createdAt,
      entryId: canonicalEntryId,
    }),
    "utf8",
  ).toString("base64url");
}

export function decodeExchangeEntryCursor(
  value: string,
  expectedDiaryId: string,
  expectedMode: ExchangeEntryMode,
): ExchangeEntryCursor | null {
  const canonicalDiaryId = canonicalizeExchangeUuid(expectedDiaryId);
  const cursor = decodeOpaqueCursor(value);

  if (
    !canonicalDiaryId ||
    typeof cursor !== "object" ||
    cursor === null ||
    !hasExactKeys(cursor, [
      "v",
      "diaryId",
      "mode",
      "direction",
      "createdAt",
      "entryId",
    ]) ||
    !("v" in cursor) ||
    !("diaryId" in cursor) ||
    !("mode" in cursor) ||
    !("direction" in cursor) ||
    !("createdAt" in cursor) ||
    !("entryId" in cursor) ||
    cursor.v !== CURSOR_VERSION ||
    typeof cursor.diaryId !== "string" ||
    !LOWERCASE_UUID_PATTERN.test(cursor.diaryId) ||
    cursor.diaryId !== canonicalDiaryId ||
    (cursor.mode !== "oldest" && cursor.mode !== "latest") ||
    cursor.mode !== expectedMode ||
    cursor.direction !== getEntryCursorDirection(cursor.mode) ||
    typeof cursor.createdAt !== "string" ||
    !isPostSearchTimestamp(cursor.createdAt) ||
    typeof cursor.entryId !== "string" ||
    !LOWERCASE_UUID_PATTERN.test(cursor.entryId)
  ) {
    return null;
  }

  return {
    v: CURSOR_VERSION,
    diaryId: cursor.diaryId,
    mode: cursor.mode,
    direction: getEntryCursorDirection(cursor.mode),
    createdAt: cursor.createdAt,
    entryId: cursor.entryId,
  };
}
