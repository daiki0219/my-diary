import {
  normalizeTagSearchQuery,
  validateSearchQuery,
} from "@/lib/search-query";

const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;

export type TagSearchCursor = {
  category: "tags";
  q: string;
  afterNormalizedName: string;
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function isCanonicalTagName(value: string) {
  const validation = validateSearchQuery("tags", value);

  return (
    validation.error === null &&
    !validation.isEmpty &&
    validation.query === value &&
    normalizeTagSearchQuery(value) === value
  );
}

export function encodeTagSearchCursor({
  q,
  afterNormalizedName,
}: Omit<TagSearchCursor, "category">) {
  if (!isCanonicalTagName(q) || !isCanonicalTagName(afterNormalizedName)) {
    throw new Error("Cannot encode an invalid tag search cursor.");
  }

  return Buffer.from(
    JSON.stringify({ category: "tags", q, afterNormalizedName }),
    "utf8",
  ).toString("base64url");
}

export function decodeTagSearchCursor(
  value: string,
  expectedQuery: string,
): TagSearchCursor | null {
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
      !hasExactKeys(cursor, ["category", "q", "afterNormalizedName"]) ||
      !("category" in cursor) ||
      !("q" in cursor) ||
      !("afterNormalizedName" in cursor) ||
      cursor.category !== "tags" ||
      typeof cursor.q !== "string" ||
      typeof cursor.afterNormalizedName !== "string" ||
      cursor.q !== expectedQuery ||
      !isCanonicalTagName(cursor.q) ||
      !isCanonicalTagName(cursor.afterNormalizedName)
    ) {
      return null;
    }

    return {
      category: "tags",
      q: cursor.q,
      afterNormalizedName: cursor.afterNormalizedName,
    };
  } catch {
    return null;
  }
}
