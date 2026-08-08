import Link from "next/link";

import { PostImageGallery } from "@/components/posts/post-image-gallery";
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
    <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
      <div className="flex min-w-0 items-center gap-3">
        <div
          aria-hidden="true"
          className="flex size-12 shrink-0 items-center justify-center rounded-full bg-orange-100 text-xl font-bold text-orange-800"
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

      <div className="mt-6 min-w-0">
        {post.title ? (
          <h1 className="break-words text-2xl font-bold leading-9 text-stone-800 [overflow-wrap:anywhere]">
            {post.title}
          </h1>
        ) : (
          <h1 className="text-2xl font-bold text-stone-800">日記の詳細</h1>
        )}

        <div className="mt-4 flex flex-wrap gap-2 text-xs">
          {post.mood && (
            <span className="rounded-full bg-orange-50 px-3 py-1 font-medium text-orange-800">
              気分：{getMoodLabel(post.mood)}
            </span>
          )}
          <span className="rounded-full bg-stone-100 px-3 py-1 font-medium text-stone-700">
            公開範囲：{getVisibilityLabel(post.visibility)}
          </span>
        </div>

        <TagList tags={post.tags} />

        <p className="mt-6 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
          {post.body}
        </p>

        <PostImageGallery eagerFirst images={post.images} />
      </div>

      <ReactionControls postId={post.id} summary={post.reactions} />

      <nav
        aria-label="日記詳細からの移動"
        className="mt-8 flex flex-wrap gap-x-5 gap-y-3 border-t border-stone-100 pt-5 text-sm font-semibold"
      >
        <Link
          className="rounded-lg text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          タイムラインへ戻る
        </Link>
        {canEditPost && (
          <Link
            className="rounded-lg text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
            href={`/posts/${post.id}/edit`}
          >
            投稿を編集
          </Link>
        )}
        {isOwnPost && (
          <Link
            className="rounded-lg text-stone-700 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
            href="/profile/posts"
          >
            自分の日記へ戻る
          </Link>
        )}
      </nav>
    </article>
  );
}
