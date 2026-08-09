import { isPostSearchTimestamp } from "@/lib/search-cursor";

const CURSOR_VERSION = 1;
const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;
const LOWERCASE_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;

export type TimelineCursorFeed = "following" | "latest";

export type TimelineCursor = {
  v: 1;
  feed: TimelineCursorFeed;
  createdAt: string;
  id: string;
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

export function encodeTimelineCursor({
  feed,
  createdAt,
  id,
}: Omit<TimelineCursor, "v">) {
  if (
    (feed !== "following" && feed !== "latest") ||
    !isPostSearchTimestamp(createdAt) ||
    !LOWERCASE_UUID_PATTERN.test(id)
  ) {
    throw new Error("Cannot encode an invalid timeline cursor.");
  }

  return Buffer.from(
    JSON.stringify({ v: CURSOR_VERSION, feed, createdAt, id }),
    "utf8",
  ).toString("base64url");
}

export function decodeTimelineCursor(
  value: string,
  expectedFeed: TimelineCursorFeed,
): TimelineCursor | null {
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
    const cursor = JSON.parse(json) as unknown;

    if (
      typeof cursor !== "object" ||
      cursor === null ||
      !hasExactKeys(cursor, ["v", "feed", "createdAt", "id"]) ||
      !("v" in cursor) ||
      !("feed" in cursor) ||
      !("createdAt" in cursor) ||
      !("id" in cursor) ||
      cursor.v !== CURSOR_VERSION ||
      (cursor.feed !== "following" && cursor.feed !== "latest") ||
      cursor.feed !== expectedFeed ||
      typeof cursor.createdAt !== "string" ||
      !isPostSearchTimestamp(cursor.createdAt) ||
      typeof cursor.id !== "string" ||
      !LOWERCASE_UUID_PATTERN.test(cursor.id)
    ) {
      return null;
    }

    return {
      v: CURSOR_VERSION,
      feed: cursor.feed,
      createdAt: cursor.createdAt,
      id: cursor.id,
    };
  } catch {
    return null;
  }
}
