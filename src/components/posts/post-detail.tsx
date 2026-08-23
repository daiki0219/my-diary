import Link from "next/link";

import { PostImageGallery } from "@/components/posts/post-image-gallery";
import { PostLocation } from "@/components/posts/post-location";
import { ReactionControls } from "@/components/posts/reaction-controls";
import { TagList } from "@/components/posts/tag-list";
import {
  getMoodLabel,
  getVisibilityLabel,
  type PostDetail as PostDetailData,
} from "@/lib/post-data";

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

export function PostDetail({
  canEditPost,
  isOwnPost,
  post,
}: {
  canEditPost: boolean;
  isOwnPost: boolean;
  post: PostDetailData;
}) {
  const normalizedUsername = post.author?.username.trim() || "ユーザー";
  const initial = Array.from(normalizedUsername)[0] ?? "人";

  return (
    <article className="min-w-0 rounded-[1.25rem] border border-border-subtle/70 bg-surface-elevated p-5 shadow-surface sm:p-8">
      <div className="flex min-w-0 items-center gap-3">
        <div
          aria-hidden="true"
          className="flex size-11 shrink-0 items-center justify-center rounded-full bg-brand-soft text-lg font-semibold text-brand-primary-hover"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <Link
            className="block break-words rounded text-[15px] font-semibold text-text-primary underline-offset-4 [overflow-wrap:anywhere] hover:text-brand-primary-hover hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            href={`/users/${post.user_id}`}
          >
            {normalizedUsername}
          </Link>
          <time
            className="mt-0.5 block text-xs text-text-muted"
            dateTime={post.created_at}
          >
            {dateFormatter.format(new Date(post.created_at))}
          </time>
        </div>
      </div>

      <div className="mt-6 min-w-0">
        {post.title ? (
          <h1 className="break-words font-brand text-2xl font-medium leading-9 tracking-[0.01em] text-text-primary [overflow-wrap:anywhere]">
            {post.title}
          </h1>
        ) : (
          <h1 className="font-brand text-2xl font-medium leading-9 tracking-[0.01em] text-text-primary">
            日記の詳細
          </h1>
        )}

        <div
          aria-label="日記の情報"
          className="mt-4 flex min-w-0 flex-wrap items-center gap-x-4 gap-y-2 border-b border-border-subtle/60 pb-5 text-sm text-text-secondary"
          role="group"
        >
          {post.mood && (
            <p className="font-medium text-brand-primary">
              {getMoodLabel(post.mood)}
            </p>
          )}
          <p className="font-medium">
            公開範囲：{getVisibilityLabel(post.visibility)}
          </p>
          <div className="min-w-0 max-w-full [&>p]:!mt-0 [&>p]:!text-sm [&>p]:!leading-6">
            <PostLocation
              locationName={post.location_name}
              variant="timeline"
            />
          </div>
        </div>

        <p className="mt-5 whitespace-pre-wrap break-words text-base leading-[1.8] text-text-primary [overflow-wrap:anywhere]">
          {post.body}
        </p>

        <div className="[&>ol]:!mt-7">
          <PostImageGallery eagerFirst images={post.images} />
        </div>

        <div className="[&>ul]:!mt-5">
          <TagList tags={post.tags} variant="timeline" />
        </div>
      </div>

      <div className="mt-7 border-t border-border-subtle/70 pt-4">
        <ReactionControls
          postId={post.id}
          summary={post.reactions}
          variant="timeline"
        />
      </div>

      {(canEditPost || isOwnPost) && (
        <nav
          aria-label="日記の操作"
          className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-sm"
        >
          {canEditPost && (
            <Link
              className="inline-flex min-h-11 items-center rounded-lg px-1 font-medium text-brand-primary-hover underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
              href={`/posts/${post.id}/edit`}
            >
              投稿を編集
            </Link>
          )}
          {isOwnPost && (
            <Link
              className="inline-flex min-h-11 items-center rounded-lg px-1 font-medium text-text-secondary underline-offset-4 hover:text-text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
              href="/profile/posts"
            >
              自分の日記へ戻る
            </Link>
          )}
        </nav>
      )}
    </article>
  );
}
