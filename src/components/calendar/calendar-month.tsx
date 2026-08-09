import Link from "next/link";

import { CalendarPostItem } from "@/components/calendar/calendar-post-item";
import {
  buildCalendarHref,
  getCalendarMonthGrid,
  type CalendarDate,
} from "@/lib/calendar";
import type { CalendarMonthData } from "@/lib/calendar-data";
import { getMoodLabel } from "@/lib/post-data";

const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"] as const;

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
  mood: CalendarMonthData["daySummaries"][number]["mood"] | null;
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

export function CalendarMonthView({ data }: { data: CalendarMonthData }) {
  const weeks = getCalendarMonthGrid(data.month);

  if (!weeks) {
    return (
      <p
        className="mt-5 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
        role="alert"
      >
        カレンダーを表示できませんでした。時間をおいてもう一度お試しください。
      </p>
    );
  }

  const summaries = new Map(
    data.daySummaries.map((summary) => [summary.date, summary]),
  );
  const monthLabel = formatMonthLabel(data.month);
  const selectedDateLabel = data.selectedDate
    ? formatDateLabel(data.selectedDate)
    : null;
  const timeFormatter = new Intl.DateTimeFormat("ja-JP", {
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
    timeZone: data.timezone,
  });

  return (
    <>
      <section
        aria-labelledby="calendar-month-heading"
        className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-3 shadow-sm sm:p-5"
      >
        <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h2
            className="text-center text-2xl font-bold tracking-tight text-stone-800 sm:text-left"
            id="calendar-month-heading"
          >
            {monthLabel}
          </h2>
          <Link
            className="inline-flex min-h-10 items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-4 py-2 text-sm font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/calendar"
          >
            今月
          </Link>
        </div>

        <nav
          aria-label="カレンダーの月移動"
          className="mt-4 grid grid-cols-2 gap-2"
        >
          {data.previousMonth ? (
            <Link
              aria-label={`前の月、${formatMonthLabel(data.previousMonth)}`}
              className="flex min-h-10 min-w-0 items-center justify-center rounded-full border border-stone-300 px-3 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={buildCalendarHref(data.previousMonth)}
            >
              ← 前月
            </Link>
          ) : (
            <span className="flex min-h-10 items-center justify-center rounded-full border border-stone-200 px-3 py-2 text-sm text-stone-400">
              ← 前月
            </span>
          )}
          {data.nextMonth ? (
            <Link
              aria-label={`次の月、${formatMonthLabel(data.nextMonth)}`}
              className="flex min-h-10 min-w-0 items-center justify-center rounded-full border border-stone-300 px-3 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={buildCalendarHref(data.nextMonth)}
            >
              次月 →
            </Link>
          ) : (
            <span className="flex min-h-10 items-center justify-center rounded-full border border-stone-200 px-3 py-2 text-sm text-stone-400">
              次月 →
            </span>
          )}
        </nav>

        <div className="mt-4 overflow-hidden rounded-2xl border border-stone-200">
          <table className="w-full table-fixed border-collapse">
            <caption className="sr-only">{monthLabel}のカレンダー</caption>
            <thead className="bg-stone-50">
              <tr>
                {WEEKDAYS.map((weekday, index) => (
                  <th
                    className={`px-0.5 py-2 text-center text-xs font-semibold sm:text-sm ${
                      index === 0
                        ? "text-red-700"
                        : index === 6
                          ? "text-blue-700"
                          : "text-stone-600"
                    }`}
                    key={weekday}
                    scope="col"
                  >
                    {weekday}
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
                          className="h-[4.75rem] border-t border-stone-200 bg-stone-50/40"
                          key={`empty-${dayIndex}`}
                        />
                      );
                    }

                    const summary = summaries.get(date);
                    const isToday = date === data.today;
                    const isSelected = date === data.selectedDate;
                    const postCount = summary?.postCount ?? 0;
                    const moodLabel = summary?.mood
                      ? getMoodLabel(summary.mood)
                      : null;
                    const moodEmoji = moodLabel
                      ? Array.from(moodLabel)[0]
                      : null;

                    return (
                      <td
                        className="border-t border-stone-200 align-top"
                        key={date}
                      >
                        <Link
                          aria-current={isSelected ? "date" : undefined}
                          aria-label={getDateAccessibleName({
                            date,
                            isToday,
                            mood: summary?.mood ?? null,
                            postCount,
                          })}
                          className={`flex min-h-[4.75rem] min-w-0 flex-col items-center gap-0.5 px-0.5 py-1 text-center transition focus-visible:relative focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-orange-600 ${
                            isSelected
                              ? "bg-orange-100 font-bold text-orange-950 shadow-[inset_0_0_0_2px_#c2410c]"
                              : "text-stone-700 hover:bg-orange-50"
                          }`}
                          href={buildCalendarHref(data.month, date)}
                        >
                          <span className="text-sm font-semibold leading-5">
                            {Number(date.slice(-2))}
                          </span>
                          {isToday && (
                            <span className="rounded bg-stone-800 px-1 py-0.5 text-[9px] font-bold leading-none text-white">
                              今日
                            </span>
                          )}
                          <span
                            aria-hidden="true"
                            className="flex min-h-4 items-center justify-center gap-0.5 text-[11px] leading-none"
                          >
                            {summary && (
                              <span className="text-orange-700">●</span>
                            )}
                            {moodEmoji && <span>{moodEmoji}</span>}
                            {isSelected && <span>✓</span>}
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

        <p className="mt-3 text-xs leading-5 text-stone-500">
          ● は投稿がある日、絵文字はその日の最新投稿の気分を表します。
        </p>
      </section>

      <section
        aria-labelledby="selected-date-heading"
        className="mt-5 min-w-0"
      >
        <h2
          className="text-xl font-bold text-stone-800"
          id="selected-date-heading"
        >
          {selectedDateLabel ? `${selectedDateLabel}の日記` : "日記を振り返る"}
        </h2>

        {!data.selectedDate ? (
          <div className="mt-3 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <p className="text-sm leading-6 text-stone-600">
              日付を選ぶと、その日の日記を振り返れます。
            </p>
          </div>
        ) : data.selectedPosts.length === 0 ? (
          <div className="mt-3 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <p className="text-sm leading-6 text-stone-600">
              この日の日記はまだありません。
            </p>
            <Link
              className="mt-4 inline-flex rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-sm font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/posts/new"
            >
              日記を書く
            </Link>
          </div>
        ) : (
          <ul
            aria-label={`${selectedDateLabel}の投稿`}
            className="mt-3 space-y-4"
          >
            {data.selectedPosts.map((post) => (
              <li className="min-w-0" key={post.id}>
                <CalendarPostItem
                  post={post}
                  timeLabel={timeFormatter.format(new Date(post.created_at))}
                />
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
