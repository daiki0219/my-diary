import Link from "next/link";

import type { CalendarMonthData } from "@/lib/calendar-data";
import {
  getMoodLabel,
  getVisibilityLabel,
} from "@/lib/post-data";
import { createPostBodyExcerpt } from "@/lib/post-excerpt";

type CalendarPost = CalendarMonthData["selectedPosts"][number];

export function CalendarPostItem({
  post,
  timeLabel,
}: {
  post: CalendarPost;
  timeLabel: string;
}) {
  const body = createPostBodyExcerpt(post.body);
  const title = post.title?.trim() || "タイトルなしの日記";

  return (
    <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
      <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          <h3 className="break-words text-lg font-bold leading-7 text-stone-800 [overflow-wrap:anywhere]">
            {title}
          </h3>
          <time
            className="mt-1 block text-xs text-stone-500"
            dateTime={post.created_at}
          >
            {timeLabel}
          </time>
        </div>
        <div className="flex flex-wrap gap-2 text-xs sm:shrink-0">
          <span className="rounded-full bg-orange-50 px-3 py-1 font-medium text-orange-800">
            {getMoodLabel(post.mood)}
          </span>
          <span className="rounded-full bg-stone-100 px-3 py-1 font-medium text-stone-700">
            {getVisibilityLabel(post.visibility)}
          </span>
        </div>
      </div>

      <p className="mt-4 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
        {body.text}
      </p>

      <Link
        aria-label={`「${title}」の投稿詳細を見る`}
        className="mt-5 inline-flex rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
        href={`/posts/${post.id}`}
      >
        投稿の詳細を見る
      </Link>
    </article>
  );
}
