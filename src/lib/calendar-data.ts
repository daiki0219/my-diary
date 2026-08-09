import type { SupabaseClient } from "@supabase/supabase-js";

import { getViewerTimeZone } from "@/lib/account-data";
import {
  buildCalendarPostIndex,
  formatInstantToCalendarDate,
  getCalendarMonthForInstant,
  getCalendarMonthUtcRange,
  getCalendarPostsForDate,
  isCalendarDateInMonth,
  parseCalendarDate,
  parseCalendarMonth,
  shiftCalendarMonth,
  type CalendarDate,
  type CalendarDaySummary,
  type CalendarMonth,
} from "@/lib/calendar";
import {
  queryCalendarPosts,
  type CalendarPostQueryRow,
} from "@/lib/calendar-query";
import {
  isPostMood,
  isPostVisibility,
  type PostMood,
} from "@/lib/post-data";

type CalendarSearchParams = {
  month?: string | string[];
  date?: string | string[];
};

type CalendarPostRow = CalendarPostQueryRow;
type CalendarDataPost = CalendarPostRow & { localDate: CalendarDate };
type CalendarDataDaySummary = CalendarDaySummary & {
  mood: PostMood | null;
};

export type CalendarMonthDataResult =
  | {
      data: {
        month: CalendarMonth;
        selectedDate: CalendarDate | null;
        timezone: string;
        today: CalendarDate;
        previousMonth: ReturnType<typeof shiftCalendarMonth>;
        nextMonth: ReturnType<typeof shiftCalendarMonth>;
        range: { start: string; end: string };
        posts: CalendarDataPost[];
        daySummaries: CalendarDataDaySummary[];
        postsByDate: Record<string, CalendarDataPost[]>;
        selectedPosts: CalendarDataPost[];
      };
      error: null;
    }
  | {
      data: null;
      error:
        | "invalid-month"
        | "invalid-date"
        | "date-outside-month"
        | "viewer-unavailable"
        | "timezone-error"
        | "query-error"
        | "invalid-data";
    };

function isCalendarPostRow(value: unknown): value is CalendarPostRow {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const row = value as Partial<Record<keyof CalendarPostRow, unknown>>;

  return (
    typeof row.id === "string" &&
    row.id.length > 0 &&
    (row.title === null || typeof row.title === "string") &&
    typeof row.body === "string" &&
    (row.mood === null ||
      (typeof row.mood === "string" && isPostMood(row.mood))) &&
    typeof row.visibility === "string" &&
    isPostVisibility(row.visibility) &&
    typeof row.created_at === "string"
  );
}

export async function getCalendarMonthData(
  supabase: SupabaseClient,
  params: CalendarSearchParams,
  now = new Date(),
): Promise<CalendarMonthDataResult> {
  const requestedMonth =
    params.month === undefined ? null : parseCalendarMonth(params.month);

  if (params.month !== undefined && !requestedMonth) {
    return { data: null, error: "invalid-month" };
  }

  const selectedDate =
    params.date === undefined ? null : parseCalendarDate(params.date);

  if (params.date !== undefined && !selectedDate) {
    return { data: null, error: "invalid-date" };
  }

  if (
    requestedMonth &&
    selectedDate &&
    !isCalendarDateInMonth(selectedDate, requestedMonth)
  ) {
    return { data: null, error: "date-outside-month" };
  }

  const viewerResult = await getViewerTimeZone(supabase);

  if (viewerResult.error || !viewerResult.userId) {
    return { data: null, error: "viewer-unavailable" };
  }

  let today: CalendarDate;

  try {
    today = formatInstantToCalendarDate(now, viewerResult.timezone);
  } catch {
    return { data: null, error: "timezone-error" };
  }

  const month =
    requestedMonth ??
    (params.month === undefined
      ? getCalendarMonthForInstant(now, viewerResult.timezone)
      : null);

  if (!month) {
    return { data: null, error: "invalid-month" };
  }

  if (selectedDate && !isCalendarDateInMonth(selectedDate, month)) {
    return { data: null, error: "date-outside-month" };
  }

  let range: { start: string; end: string };

  try {
    range = getCalendarMonthUtcRange(month, viewerResult.timezone);
  } catch {
    return { data: null, error: "timezone-error" };
  }

  let postsResult;

  try {
    postsResult = await queryCalendarPosts(
      supabase,
      viewerResult.userId,
      range,
    );
  } catch {
    return { data: null, error: "query-error" };
  }

  if (
    postsResult.error ||
    !postsResult.data ||
    !postsResult.data.every(isCalendarPostRow)
  ) {
    return {
      data: null,
      error: postsResult.error ? "query-error" : "invalid-data",
    };
  }

  const index = buildCalendarPostIndex(
    postsResult.data,
    month,
    viewerResult.timezone,
  );

  if (!index) {
    return { data: null, error: "invalid-data" };
  }

  const selectedPosts = selectedDate
    ? getCalendarPostsForDate(index, month, selectedDate)
    : [];

  if (!selectedPosts) {
    return { data: null, error: "invalid-data" };
  }

  return {
    data: {
      month,
      selectedDate,
      timezone: viewerResult.timezone,
      today,
      previousMonth: shiftCalendarMonth(month, -1),
      nextMonth: shiftCalendarMonth(month, 1),
      range,
      posts: index.posts as CalendarDataPost[],
      daySummaries: index.daySummaries as CalendarDataDaySummary[],
      postsByDate: index.postsByDate as Record<string, CalendarDataPost[]>,
      selectedPosts: selectedPosts as CalendarDataPost[],
    },
    error: null,
  };
}
