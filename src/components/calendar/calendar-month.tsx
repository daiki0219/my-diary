import Link from "next/link";

import { CalendarPostItem } from "@/components/calendar/calendar-post-item";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { Surface } from "@/components/ui/surface";
import {
  buildCalendarHref,
  getCalendarMonthGrid,
  type CalendarDate,
} from "@/lib/calendar";
import type { CalendarMonthData } from "@/lib/calendar-data";
import { getMoodLabel } from "@/lib/post-data";

const WEEKDAYS = [
  ["日", "日曜日"],
  ["月", "月曜日"],
  ["火", "火曜日"],
  ["水", "水曜日"],
  ["木", "木曜日"],
  ["金", "金曜日"],
  ["土", "土曜日"],
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
      <FeedbackPanel
        className="mt-6 max-w-2xl"
        role="alert"
        variant="error"
      >
        カレンダーを表示できませんでした。時間をおいてもう一度お試しください。
      </FeedbackPanel>
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
    <div className="mt-6 grid min-w-0 gap-6 lg:grid-cols-[minmax(0,1.35fr)_minmax(20rem,0.9fr)] lg:items-start">
      <Surface
        as="section"
        aria-labelledby="calendar-month-heading"
        className="min-w-0 border border-border-subtle/70 p-3 shadow-surface sm:p-5"
        variant="elevated"
      >
        <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <h2
            className="text-center text-2xl font-semibold tracking-tight text-text-primary sm:text-left"
            id="calendar-month-heading"
          >
            {monthLabel}
          </h2>
          <ActionLink href="/calendar" variant="secondary">
            今月
          </ActionLink>
        </div>

        <nav
          aria-label="カレンダーの月移動"
          className="mt-4 grid grid-cols-2 gap-2"
        >
          {data.previousMonth ? (
            <ActionLink
              aria-label={`前の月、${formatMonthLabel(data.previousMonth)}`}
              className="min-w-0 px-3"
              href={buildCalendarHref(data.previousMonth)}
              variant="neutral"
            >
              ← 前月
            </ActionLink>
          ) : (
            <span className="flex min-h-11 items-center justify-center rounded-control border border-border-subtle px-3 py-2 text-sm text-control-disabled-text">
              ← 前月
            </span>
          )}
          {data.nextMonth ? (
            <ActionLink
              aria-label={`次の月、${formatMonthLabel(data.nextMonth)}`}
              className="min-w-0 px-3"
              href={buildCalendarHref(data.nextMonth)}
              variant="neutral"
            >
              次月 →
            </ActionLink>
          ) : (
            <span className="flex min-h-11 items-center justify-center rounded-control border border-border-subtle px-3 py-2 text-sm text-control-disabled-text">
              次月 →
            </span>
          )}
        </nav>

        <div className="mt-4 overflow-hidden rounded-control border border-border-subtle">
          <table className="w-full table-fixed border-collapse">
            <caption className="sr-only">{monthLabel}のカレンダー</caption>
            <thead className="bg-surface-muted">
              <tr>
                {WEEKDAYS.map(([weekday, weekdayLabel], index) => (
                  <th
                    className={`px-0.5 py-2 text-center text-xs font-semibold sm:text-sm ${index === 0 ? "text-danger" : "text-text-secondary"}`}
                    key={weekday}
                    scope="col"
                  >
                    <span aria-hidden="true">{weekday}</span>
                    <span className="sr-only">{weekdayLabel}</span>
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
                          className="h-[4.5rem] border-t border-border-subtle bg-surface-muted/40"
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
                        className="border-t border-border-subtle align-top"
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
                          className={`flex min-h-[4.5rem] min-w-0 flex-col items-center gap-0.5 px-0.5 py-1 text-center transition focus-visible:relative focus-visible:z-10 focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-focus ${
                            isSelected
                              ? "bg-brand-soft font-semibold text-text-primary ring-2 ring-inset ring-brand-primary"
                              : "text-text-secondary hover:bg-surface-muted"
                          }`}
                          href={buildCalendarHref(data.month, date)}
                        >
                          <span className="text-sm font-semibold leading-5">
                            {Number(date.slice(-2))}
                          </span>
                          {isToday && (
                            <span className="rounded bg-text-primary px-1 py-0.5 text-[9px] font-bold leading-none text-white">
                              今日
                            </span>
                          )}
                          <span
                            aria-hidden="true"
                            className="flex min-h-4 items-center justify-center gap-0.5 text-[11px] leading-none"
                          >
                            {summary && (
                              <span className="text-brand-primary">●</span>
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

        <p className="mt-3 text-xs leading-5 text-text-muted">
          ● は投稿がある日、絵文字はその日の最新投稿の気分を表します。
        </p>
      </Surface>

      <section
        aria-labelledby="selected-date-heading"
        className="min-w-0"
      >
        <h2
          className="text-xl font-semibold tracking-tight text-text-primary"
          id="selected-date-heading"
        >
          {selectedDateLabel ? `${selectedDateLabel}の日記` : "日記を振り返る"}
        </h2>

        {!data.selectedDate ? (
          <EmptyState
            className="mt-3"
            description="カレンダーの日付を選ぶと、その日の日記を振り返れます。"
            title="日付を選んでください"
            titleAs="h3"
          />
        ) : data.selectedPosts.length === 0 ? (
          <EmptyState
            action={
              <ActionLink href="/posts/new" variant="secondary">
                日記を書く
              </ActionLink>
            }
            className="mt-3"
            description="この日の日記はまだありません。"
            title="記録がない日です"
            titleAs="h3"
          />
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
    </div>
  );
}
