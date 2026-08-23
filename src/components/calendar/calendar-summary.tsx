import Link from "next/link";

import { Surface } from "@/components/ui/surface";
import {
  buildCalendarHref,
  getCalendarMonthGrid,
  type CalendarDate,
} from "@/lib/calendar";
import type { CalendarMonthSummaryData } from "@/lib/calendar-data";
import { getMoodLabel } from "@/lib/post-data";

const WEEKDAYS = [
  { label: "日曜日", shortLabel: "日" },
  { label: "月曜日", shortLabel: "月" },
  { label: "火曜日", shortLabel: "火" },
  { label: "水曜日", shortLabel: "水" },
  { label: "木曜日", shortLabel: "木" },
  { label: "金曜日", shortLabel: "金" },
  { label: "土曜日", shortLabel: "土" },
] as const;

function formatMonthLabel(month: string) {
  const [year, monthNumber] = month.split("-").map(Number);
  return `${year}年${monthNumber}月`;
}

function formatDateLabel(date: string) {
  const [year, month, day] = date.split("-").map(Number);
  return `${year}年${month}月${day}日`;
}

function getDateAccessibleName({
  date,
  isToday,
  mood,
  postCount,
}: {
  date: CalendarDate;
  isToday: boolean;
  mood: CalendarMonthSummaryData["daySummaries"][number]["mood"] | null;
  postCount: number;
}) {
  const details = [formatDateLabel(date)];

  if (isToday) {
    details.push("今日");
  }

  if (postCount > 0) {
    details.push(`投稿${postCount}件`);

    if (mood) {
      details.push(`最新の気分 ${getMoodLabel(mood)}`);
    }
  }

  return details.join("、");
}

function CalendarSummaryFallback() {
  return (
    <Surface className="p-5">
      <div className="flex items-center justify-between gap-3">
        <h2
          className="text-lg font-semibold text-text-primary"
          id="home-calendar-heading"
        >
          カレンダー
        </h2>
        <Link
          className="inline-flex min-h-10 items-center gap-1 rounded-lg px-2 text-sm font-medium text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          href="/calendar"
        >
          見る<span aria-hidden="true">→</span>
        </Link>
      </div>
      <p className="mt-3 text-sm leading-6 text-text-secondary">
        日記を日付からゆっくり振り返れます。
      </p>
    </Surface>
  );
}

export function CalendarSummary({
  data,
}: {
  data: CalendarMonthSummaryData | null;
}) {
  const weeks = data ? getCalendarMonthGrid(data.month) : null;

  if (!data || !weeks) {
    return <CalendarSummaryFallback />;
  }

  const summaries = new Map(
    data.daySummaries.map((summary) => [summary.date, summary]),
  );
  const monthLabel = formatMonthLabel(data.month);

  return (
    <Surface className="p-5 xl:p-6">
      <div className="flex items-center justify-between gap-3">
        <h2
          className="text-lg font-semibold text-text-primary"
          id="home-calendar-heading"
        >
          カレンダー
        </h2>
        <Link
          className="inline-flex min-h-10 items-center gap-1 rounded-lg px-2 text-sm font-medium text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          href={buildCalendarHref(data.month)}
        >
          今月を見る<span aria-hidden="true">→</span>
        </Link>
      </div>
      <p className="mt-2 text-sm font-medium text-text-secondary">
        {monthLabel}
      </p>

      <div className="mt-3">
        <table className="w-full table-fixed border-separate border-spacing-x-0 border-spacing-y-1">
          <caption className="sr-only">{monthLabel}の日記カレンダー</caption>
          <thead>
            <tr>
              {WEEKDAYS.map((weekday, index) => (
                <th
                  className={`py-1 text-center text-[11px] font-semibold xl:text-xs ${
                    index === 0
                      ? "text-danger"
                      : index === 6
                        ? "text-blue-700"
                        : "text-text-muted"
                  }`}
                  key={weekday.shortLabel}
                  scope="col"
                >
                  <span aria-hidden="true">{weekday.shortLabel}</span>
                  <span className="sr-only">{weekday.label}</span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {weeks.map((week, weekIndex) => (
              <tr key={weekIndex}>
                {week.map((date, dayIndex) => {
                  if (!date) {
                    return (
                      <td
                        aria-hidden="true"
                        className="h-10"
                        key={`empty-${dayIndex}`}
                      />
                    );
                  }

                  const summary = summaries.get(date);
                  const isToday = date === data.today;
                  const postCount = summary?.postCount ?? 0;
                  const moodLabel = summary?.mood
                    ? getMoodLabel(summary.mood)
                    : null;
                  const moodEmoji = moodLabel
                    ? Array.from(moodLabel)[0]
                    : null;

                  return (
                    <td className="align-top" key={date}>
                      <Link
                        aria-current={isToday ? "date" : undefined}
                        aria-label={getDateAccessibleName({
                          date,
                          isToday,
                          mood: summary?.mood ?? null,
                          postCount,
                        })}
                        className="flex min-h-10 min-w-0 flex-col items-center justify-center gap-0.5 rounded-control text-center text-text-secondary transition hover:bg-surface-muted focus-visible:relative focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-focus"
                        href={buildCalendarHref(data.month, date)}
                      >
                        <span
                          className={`flex size-7 items-center justify-center rounded-full text-xs font-medium leading-none ${
                            isToday
                              ? "bg-brand-primary font-semibold text-white shadow-sm"
                              : ""
                          }`}
                        >
                          {Number(date.slice(-2))}
                        </span>
                        <span
                          aria-hidden="true"
                          className="flex min-h-3 items-center justify-center gap-px text-[9px] leading-none"
                        >
                          {summary && (
                            <span className="text-brand-primary">●</span>
                          )}
                          {moodEmoji && <span>{moodEmoji}</span>}
                        </span>
                      </Link>
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="mt-2 text-[11px] leading-5 text-text-muted">
        ● は日記がある日、丸い日付は今日、絵文字は最新の気分です。
      </p>
    </Surface>
  );
}
