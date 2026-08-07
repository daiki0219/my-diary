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

export type PostSearchCursor = {
  category: "posts";
  q: string;
  beforeCreatedAt: string;
  beforeId: string;
};

const LOWERCASE_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u;
const POST_SEARCH_TIMESTAMP_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|([+-])(\d{2}):(\d{2}))$/u;

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

function isCanonicalPostSearchQuery(value: string) {
  const validation = validateSearchQuery("posts", value);

  return (
    validation.error === null &&
    !validation.isEmpty &&
    validation.query === value
  );
}

function isLeapYear(year: number) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function getDaysInMonth(year: number, month: number) {
  if (month === 2) {
    return isLeapYear(year) ? 29 : 28;
  }

  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

function daysSinceUnixEpoch(year: number, month: number, day: number) {
  const adjustedYear = month <= 2 ? year - 1 : year;
  const era = Math.floor(adjustedYear / 400);
  const yearOfEra = adjustedYear - era * 400;
  const adjustedMonth = month > 2 ? month - 3 : month + 9;
  const dayOfYear = Math.floor((153 * adjustedMonth + 2) / 5) + day - 1;
  const dayOfEra =
    yearOfEra * 365 +
    Math.floor(yearOfEra / 4) -
    Math.floor(yearOfEra / 100) +
    dayOfYear;

  return era * 146097 + dayOfEra - 719468;
}

function parsePostSearchTimestamp(value: string) {
  const match = POST_SEARCH_TIMESTAMP_PATTERN.exec(value);

  if (!match) {
    return null;
  }

  const [, yearText, monthText, dayText, hourText, minuteText, secondText] =
    match;
  const fractionText = match[7] ?? "";
  const timezone = match[8];
  const offsetSign = match[9];
  const offsetHourText = match[10];
  const offsetMinuteText = match[11];
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = Number(secondText);
  const offsetHour = timezone === "Z" ? 0 : Number(offsetHourText);
  const offsetMinute = timezone === "Z" ? 0 : Number(offsetMinuteText);

  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > getDaysInMonth(year, month) ||
    hour > 23 ||
    minute > 59 ||
    second > 59 ||
    offsetHour > 15 ||
    offsetMinute > 59
  ) {
    return null;
  }

  const localMicroseconds =
    BigInt(daysSinceUnixEpoch(year, month, day)) * BigInt("86400000000") +
    BigInt(hour * 3_600 + minute * 60 + second) * BigInt("1000000") +
    BigInt(fractionText.padEnd(6, "0") || "0");
  const offsetMicroseconds =
    BigInt(offsetHour * 60 + offsetMinute) * BigInt("60000000");

  if (timezone === "Z") {
    return localMicroseconds;
  }

  return offsetSign === "+"
    ? localMicroseconds - offsetMicroseconds
    : localMicroseconds + offsetMicroseconds;
}

export function isPostSearchTimestamp(value: string) {
  return parsePostSearchTimestamp(value) !== null;
}

export function comparePostSearchRows(
  left: { id: string; created_at: string },
  right: { id: string; created_at: string },
) {
  const leftTimestamp = parsePostSearchTimestamp(left.created_at);
  const rightTimestamp = parsePostSearchTimestamp(right.created_at);

  if (leftTimestamp === null || rightTimestamp === null) {
    throw new Error("Cannot compare an invalid post search timestamp.");
  }

  if (leftTimestamp > rightTimestamp) {
    return -1;
  }

  if (leftTimestamp < rightTimestamp) {
    return 1;
  }

  if (left.id > right.id) {
    return -1;
  }

  if (left.id < right.id) {
    return 1;
  }

  return 0;
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

export function encodePostSearchCursor({
  q,
  beforeCreatedAt,
  beforeId,
}: Omit<PostSearchCursor, "category">) {
  if (
    !isCanonicalPostSearchQuery(q) ||
    !isPostSearchTimestamp(beforeCreatedAt) ||
    !LOWERCASE_UUID_PATTERN.test(beforeId)
  ) {
    throw new Error("Cannot encode an invalid post search cursor.");
  }

  return Buffer.from(
    JSON.stringify({
      category: "posts",
      q,
      beforeCreatedAt,
      beforeId,
    }),
    "utf8",
  ).toString("base64url");
}

export function decodePostSearchCursor(
  value: string,
  expectedQuery: string,
): PostSearchCursor | null {
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
      !hasExactKeys(cursor, [
        "category",
        "q",
        "beforeCreatedAt",
        "beforeId",
      ]) ||
      !("category" in cursor) ||
      !("q" in cursor) ||
      !("beforeCreatedAt" in cursor) ||
      !("beforeId" in cursor) ||
      cursor.category !== "posts" ||
      typeof cursor.q !== "string" ||
      typeof cursor.beforeCreatedAt !== "string" ||
      typeof cursor.beforeId !== "string" ||
      cursor.q !== expectedQuery ||
      !isCanonicalPostSearchQuery(cursor.q) ||
      !isPostSearchTimestamp(cursor.beforeCreatedAt) ||
      !LOWERCASE_UUID_PATTERN.test(cursor.beforeId)
    ) {
      return null;
    }

    return {
      category: "posts",
      q: cursor.q,
      beforeCreatedAt: cursor.beforeCreatedAt,
      beforeId: cursor.beforeId,
    };
  } catch {
    return null;
  }
}
