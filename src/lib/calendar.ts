export type CalendarMonth = string & { readonly __calendarMonth: unique symbol };
export type CalendarDate = string & { readonly __calendarDate: unique symbol };

export type CalendarPostInput = {
  id: string;
  title: string | null;
  body: string;
  mood: string | null;
  visibility: string;
  created_at: string;
};

export type CalendarPost = CalendarPostInput & {
  localDate: CalendarDate;
};

export type CalendarDaySummary = {
  date: CalendarDate;
  hasPosts: true;
  postCount: number;
  mood: string | null;
};

export type CalendarPostIndex = {
  posts: CalendarPost[];
  daySummaries: CalendarDaySummary[];
  postsByDate: Record<string, CalendarPost[]>;
};

type LocalDateTimeParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

const MONTH_PATTERN = /^(\d{4})-(\d{2})$/;
const DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const POSTGRES_INSTANT_PATTERN =
  /^(\d{4,})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:\d{2})$/;
const MILLISECONDS_PER_DAY = 24 * 60 * 60 * 1_000;
const BOUNDARY_SEARCH_RADIUS = 3 * MILLISECONDS_PER_DAY;
const BOUNDARY_SEARCH_STEP = 6 * 60 * 60 * 1_000;

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function getFormatter(timezone: string) {
  const cached = formatterCache.get(timezone);

  if (cached) {
    return cached;
  }

  const formatter = new Intl.DateTimeFormat(
    "en-CA-u-ca-iso8601-nu-latn",
    {
      calendar: "iso8601",
      numberingSystem: "latn",
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    },
  );

  formatterCache.set(timezone, formatter);
  return formatter;
}

function getLocalDateTimeParts(
  instantMilliseconds: number,
  timezone: string,
): LocalDateTimeParts {
  if (!Number.isFinite(instantMilliseconds)) {
    throw new RangeError("Invalid instant.");
  }

  const parts = new Map(
    getFormatter(timezone)
      .formatToParts(instantMilliseconds)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  );
  const result = {
    year: Number(parts.get("year")),
    month: Number(parts.get("month")),
    day: Number(parts.get("day")),
    hour: Number(parts.get("hour")),
    minute: Number(parts.get("minute")),
    second: Number(parts.get("second")),
  };

  if (Object.values(result).some((value) => !Number.isInteger(value))) {
    throw new RangeError("Timezone conversion failed.");
  }

  return result;
}

function getCalendarMonthOrdinal(parts: Pick<LocalDateTimeParts, "year" | "month">) {
  return parts.year * 12 + parts.month - 1;
}

function getUtcMilliseconds(
  year: number,
  month: number,
  day: number,
) {
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(0, 0, 0, 0);
  return date.getTime();
}

function findCalendarMonthBoundary(
  year: number,
  month: number,
  timezone: string,
) {
  const targetOrdinal = year * 12 + month - 1;
  const approximateBoundary = getUtcMilliseconds(year, month, 1);
  const searchStart = approximateBoundary - BOUNDARY_SEARCH_RADIUS;
  const searchEnd = approximateBoundary + BOUNDARY_SEARCH_RADIUS;
  let previousInstant = searchStart;
  let previousOrdinal = getCalendarMonthOrdinal(
    getLocalDateTimeParts(previousInstant, timezone),
  );

  for (
    let instant = searchStart + BOUNDARY_SEARCH_STEP;
    instant <= searchEnd;
    instant += BOUNDARY_SEARCH_STEP
  ) {
    const ordinal = getCalendarMonthOrdinal(
      getLocalDateTimeParts(instant, timezone),
    );

    if (previousOrdinal < targetOrdinal && ordinal >= targetOrdinal) {
      let low = previousInstant;
      let high = instant;

      while (low + 1 < high) {
        const middle = low + Math.floor((high - low) / 2);
        const middleOrdinal = getCalendarMonthOrdinal(
          getLocalDateTimeParts(middle, timezone),
        );

        if (middleOrdinal >= targetOrdinal) {
          high = middle;
        } else {
          low = middle;
        }
      }

      if (
        getCalendarMonthOrdinal(getLocalDateTimeParts(high, timezone)) !==
        targetOrdinal
      ) {
        throw new RangeError("Local calendar month does not exist.");
      }

      return high;
    }

    previousInstant = instant;
    previousOrdinal = ordinal;
  }

  throw new RangeError("Calendar month boundary was not found.");
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

function formatMonth(year: number, month: number) {
  return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}` as CalendarMonth;
}

function formatDate(year: number, month: number, day: number) {
  return `${formatMonth(year, month)}-${String(day).padStart(2, "0")}` as CalendarDate;
}

function parsePostgresInstantOrder(value: string) {
  const match = POSTGRES_INSTANT_PATTERN.exec(value);

  if (!match) {
    return null;
  }

  const [, year, month, day, hour, minute, second, fraction = "", zone] =
    match;
  const wholeSecond = Date.parse(
    `${year}-${month}-${day}T${hour}:${minute}:${second}${zone}`,
  );

  if (!Number.isFinite(wholeSecond)) {
    return null;
  }

  return {
    wholeSecond,
    fraction: fraction.slice(0, 9).padEnd(9, "0"),
  };
}

function comparePostInstantsDescending(
  left: CalendarPostInput,
  right: CalendarPostInput,
) {
  const leftInstant = parsePostgresInstantOrder(left.created_at);
  const rightInstant = parsePostgresInstantOrder(right.created_at);

  if (!leftInstant || !rightInstant) {
    throw new RangeError("Invalid post timestamp.");
  }

  if (leftInstant.wholeSecond !== rightInstant.wholeSecond) {
    return rightInstant.wholeSecond - leftInstant.wholeSecond;
  }

  if (leftInstant.fraction !== rightInstant.fraction) {
    return leftInstant.fraction < rightInstant.fraction ? 1 : -1;
  }

  if (left.id === right.id) {
    return 0;
  }

  return left.id < right.id ? 1 : -1;
}

export function parseCalendarMonth(value: unknown): CalendarMonth | null {
  if (typeof value !== "string") {
    return null;
  }

  const match = MONTH_PATTERN.exec(value);

  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);

  if (year < 1 || month < 1 || month > 12) {
    return null;
  }

  return value as CalendarMonth;
}

export function parseCalendarDate(value: unknown): CalendarDate | null {
  if (typeof value !== "string") {
    return null;
  }

  const match = DATE_PATTERN.exec(value);

  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);

  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > getDaysInMonth(year, month)
  ) {
    return null;
  }

  return value as CalendarDate;
}

export function isCalendarDateInMonth(
  date: CalendarDate,
  month: CalendarMonth,
) {
  return date.startsWith(`${month}-`);
}

export function shiftCalendarMonth(
  month: CalendarMonth,
  offset: -1 | 1,
): CalendarMonth | null {
  const match = MONTH_PATTERN.exec(month);

  if (!match) {
    return null;
  }

  const year = Number(match[1]);
  const monthNumber = Number(match[2]);
  const shiftedMonth = monthNumber + offset;
  const shiftedYear =
    shiftedMonth === 0 ? year - 1 : shiftedMonth === 13 ? year + 1 : year;
  const normalizedMonth =
    shiftedMonth === 0 ? 12 : shiftedMonth === 13 ? 1 : shiftedMonth;

  if (shiftedYear < 1 || shiftedYear > 9_999) {
    return null;
  }

  return formatMonth(shiftedYear, normalizedMonth);
}

export function getCalendarMonthForInstant(
  instant: Date | number | string,
  timezone: string,
) {
  return formatInstantToCalendarDate(instant, timezone).slice(
    0,
    7,
  ) as CalendarMonth;
}

export function formatInstantToCalendarDate(
  instant: Date | number | string,
  timezone: string,
) {
  const instantMilliseconds =
    instant instanceof Date
      ? instant.getTime()
      : typeof instant === "number"
        ? instant
        : Date.parse(instant);
  const parts = getLocalDateTimeParts(instantMilliseconds, timezone);
  return formatDate(parts.year, parts.month, parts.day);
}

export function getCalendarMonthUtcRange(
  month: CalendarMonth,
  timezone: string,
) {
  const match = MONTH_PATTERN.exec(month);

  if (!match) {
    throw new RangeError("Invalid calendar month.");
  }

  const year = Number(match[1]);
  const monthNumber = Number(match[2]);
  const nextYear = monthNumber === 12 ? year + 1 : year;
  const nextMonth = monthNumber === 12 ? 1 : monthNumber + 1;
  const start = findCalendarMonthBoundary(year, monthNumber, timezone);
  const end = findCalendarMonthBoundary(nextYear, nextMonth, timezone);

  if (start >= end) {
    throw new RangeError("Invalid calendar month range.");
  }

  return {
    start: new Date(start).toISOString(),
    end: new Date(end).toISOString(),
  };
}

export function buildCalendarPostIndex(
  rawPosts: readonly CalendarPostInput[],
  month: CalendarMonth,
  timezone: string,
): CalendarPostIndex | null {
  let orderedPosts: CalendarPostInput[];

  try {
    orderedPosts = [...rawPosts].sort(comparePostInstantsDescending);
  } catch {
    return null;
  }

  const posts: CalendarPost[] = [];
  const postsByDate: Record<string, CalendarPost[]> = {};
  const seenPostIds = new Set<string>();

  for (const rawPost of orderedPosts) {
    if (seenPostIds.has(rawPost.id)) {
      return null;
    }

    let localDate: CalendarDate;

    try {
      localDate = formatInstantToCalendarDate(rawPost.created_at, timezone);
    } catch {
      return null;
    }

    if (!isCalendarDateInMonth(localDate, month)) {
      return null;
    }

    const post = { ...rawPost, localDate };
    seenPostIds.add(post.id);
    posts.push(post);
    (postsByDate[localDate] ??= []).push(post);
  }

  const daySummaries = Object.entries(postsByDate)
    .map(([date, dayPosts]) => ({
      date: date as CalendarDate,
      hasPosts: true as const,
      postCount: dayPosts.length,
      mood: dayPosts[0]?.mood ?? null,
    }))
    .sort((left, right) => left.date.localeCompare(right.date));

  return { posts, daySummaries, postsByDate };
}

export function getCalendarPostsForDate(
  index: CalendarPostIndex,
  month: CalendarMonth,
  date: unknown,
) {
  const parsedDate = parseCalendarDate(date);

  if (!parsedDate || !isCalendarDateInMonth(parsedDate, month)) {
    return null;
  }

  return index.postsByDate[parsedDate] ?? [];
}
