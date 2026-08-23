import Link from "next/link";

import { CollapsiblePostBody } from "@/components/posts/collapsible-post-body";
import { CommentCount } from "@/components/posts/comment-count";
import { PostImageGallery } from "@/components/posts/post-image-gallery";
import { PostLocation } from "@/components/posts/post-location";
import { ReactionControls } from "@/components/posts/reaction-controls";
import { TagList } from "@/components/posts/tag-list";
import { getMoodLabel, type TimelinePost } from "@/lib/post-data";

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

export function TimelinePostCard({ post }: { post: TimelinePost }) {
  const normalizedUsername = post.author?.username.trim() || "ユーザー";
  const initial = Array.from(normalizedUsername)[0] ?? "人";

  return (
    <article className="min-w-0 rounded-[1.25rem] border border-border-subtle/70 bg-surface-elevated p-4 shadow-surface sm:p-5">
      <div className="flex min-w-0 items-center gap-3">
        <div
          aria-hidden="true"
          className="flex size-10 shrink-0 items-center justify-center rounded-full bg-brand-soft text-base font-semibold text-brand-primary-hover"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <div className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <Link
              className="min-w-0 break-words rounded text-[15px] font-semibold text-text-primary underline-offset-4 [overflow-wrap:anywhere] hover:text-brand-primary-hover hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
              href={`/users/${post.user_id}`}
            >
              {normalizedUsername}
            </Link>
            <span aria-hidden="true" className="text-xs text-text-muted">
              ·
            </span>
            <time
              className="text-xs text-text-muted"
              dateTime={post.created_at}
            >
              {dateFormatter.format(new Date(post.created_at))}
            </time>
          </div>
          <p className="mt-1 text-sm font-medium text-brand-primary">
            {getMoodLabel(post.mood)}
          </p>
        </div>
      </div>

      {post.title && (
        <h2 className="mt-3 break-words font-brand text-lg font-medium leading-7 tracking-[0.01em] text-text-primary [overflow-wrap:anywhere]">
          {post.title}
        </h2>
      )}

      <PostLocation locationName={post.location_name} variant="timeline" />

      <CollapsiblePostBody body={post.body} title={post.title} />

      <div className="[&>ol]:!mt-3">
        <PostImageGallery images={post.images} />
      </div>

      <TagList tags={post.tags} variant="timeline" />

      <div className="mt-4 border-t border-border-subtle/70 pt-2">
        <ReactionControls
          postId={post.id}
          summary={post.reactions}
          variant="timeline"
        />
        <div className="flex min-w-0 flex-wrap items-center justify-between gap-x-4 gap-y-0.5">
          <CommentCount count={post.commentCount} variant="timeline" />
          <Link
            className="inline-flex min-h-11 items-center rounded-lg text-sm font-medium text-brand-primary-hover underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            href={`/posts/${post.id}`}
          >
            詳細を見る
          </Link>
        </div>
      </div>
    </article>
  );
}
