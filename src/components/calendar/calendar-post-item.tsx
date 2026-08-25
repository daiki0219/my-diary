import { ActionLink } from "@/components/ui/actions";
import { Surface } from "@/components/ui/surface";
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
    <Surface
      as="article"
      className="min-w-0 border border-border-subtle/70 p-4 shadow-surface sm:p-5"
      variant="elevated"
    >
      <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-muted">
        <time dateTime={post.created_at}>{timeLabel}</time>
        <span aria-hidden="true">·</span>
        <span className="font-medium text-brand-primary">
          {getMoodLabel(post.mood)}
        </span>
        <span
          aria-label={`公開範囲：${getVisibilityLabel(post.visibility)}`}
          className="inline-flex min-h-7 items-center rounded-full bg-surface-muted/70 px-2.5 font-medium text-text-secondary"
        >
          {getVisibilityLabel(post.visibility)}
        </span>
      </div>

      <h3 className="mt-3 break-words font-brand text-xl font-medium leading-8 tracking-[0.01em] text-text-primary [overflow-wrap:anywhere]">
        {title}
      </h3>

      <p className="mt-2.5 whitespace-pre-wrap break-words text-[15px] leading-7 text-text-secondary [overflow-wrap:anywhere]">
        {body.text}
      </p>

      <ActionLink
        aria-label={`「${title}」の投稿詳細を見る`}
        className="-ml-3 mt-3"
        href={`/posts/${post.id}`}
        variant="quiet"
      >
        投稿の詳細を見る
      </ActionLink>
    </Surface>
  );
}
