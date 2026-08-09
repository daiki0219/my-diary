import Link from "next/link";

import { CommentCount } from "@/components/posts/comment-count";
import { PostImageGallery } from "@/components/posts/post-image-gallery";
import { ReactionControls } from "@/components/posts/reaction-controls";
import { TagList } from "@/components/posts/tag-list";
import { getMoodLabel, type TimelinePost } from "@/lib/post-data";
import { createPostBodyExcerpt } from "@/lib/post-excerpt";

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

export function TimelinePostCard({
  post,
  showBodyExcerpt = false,
}: {
  post: TimelinePost;
  showBodyExcerpt?: boolean;
}) {
  const normalizedUsername = post.author?.username.trim() || "ユーザー";
  const initial = Array.from(normalizedUsername)[0] ?? "人";
  const body = showBodyExcerpt
    ? createPostBodyExcerpt(post.body)
    : { text: post.body, isTruncated: false };

  return (
    <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
      <div className="flex min-w-0 items-center gap-3">
        <div
          aria-hidden="true"
          className="flex size-11 shrink-0 items-center justify-center rounded-full bg-orange-100 text-lg font-bold text-orange-800"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <Link
            className="block break-words rounded font-semibold text-stone-800 underline-offset-4 [overflow-wrap:anywhere] hover:text-orange-700 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={`/users/${post.user_id}`}
          >
            {normalizedUsername}
          </Link>
          <time
            className="mt-0.5 block text-xs text-stone-500"
            dateTime={post.created_at}
          >
            {dateFormatter.format(new Date(post.created_at))}
          </time>
        </div>
      </div>

      <div className="mt-4 flex min-w-0 flex-col gap-2">
        {post.title && (
          <h2 className="break-words text-xl font-bold leading-8 text-stone-800 [overflow-wrap:anywhere]">
            {post.title}
          </h2>
        )}
        <div className="flex flex-wrap gap-2 text-xs">
          <span className="rounded-full bg-orange-50 px-3 py-1 font-medium text-orange-800">
            {getMoodLabel(post.mood)}
          </span>
        </div>
      </div>

      <TagList tags={post.tags} />

      <p className="mt-4 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
        {body.text}
      </p>

      {body.isTruncated && (
        <Link
          aria-label={
            post.title
              ? `投稿「${post.title}」を続きを読む`
              : "この投稿を続きを読む"
          }
          className="mt-2 inline-flex rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href={`/posts/${post.id}`}
        >
          続きを読む
        </Link>
      )}

      <PostImageGallery images={post.images} />

      <ReactionControls postId={post.id} summary={post.reactions} />
      <CommentCount count={post.commentCount} />

      <Link
        className="mt-5 inline-flex rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
        href={`/posts/${post.id}`}
      >
        詳細を見る
      </Link>
    </article>
  );
}
