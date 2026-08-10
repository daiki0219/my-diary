import Link from "next/link";

import { CommentCount } from "@/components/posts/comment-count";
import { DeletePostButton } from "@/components/posts/delete-post-button";
import { PostImageGallery } from "@/components/posts/post-image-gallery";
import { PostLocation } from "@/components/posts/post-location";
import { ReactionControls } from "@/components/posts/reaction-controls";
import { TagList } from "@/components/posts/tag-list";
import {
  getMoodLabel,
  getVisibilityLabel,
  type Post,
} from "@/lib/post-data";

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

export function PostCard({
  canDeletePost,
  post,
}: {
  canDeletePost: boolean;
  post: Post;
}) {
  const createdAt = new Date(post.created_at);

  return (
    <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
      <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <div className="min-w-0">
          {post.title && (
            <h2 className="break-words text-xl font-bold leading-8 text-stone-800 [overflow-wrap:anywhere]">
              {post.title}
            </h2>
          )}
          <time
            className={`block text-xs text-stone-500 ${
              post.title ? "mt-1" : ""
            }`}
            dateTime={post.created_at}
          >
            {dateFormatter.format(createdAt)}
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

      <PostLocation locationName={post.location_name} />

      <TagList tags={post.tags} />

      <p className="mt-4 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
        {post.body}
      </p>

      <PostImageGallery images={post.images} />

      <ReactionControls postId={post.id} summary={post.reactions} />
      <CommentCount count={post.commentCount} />

      <Link
        className="mt-5 inline-flex rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
        href={`/posts/${post.id}`}
      >
        詳細を見る
      </Link>

      {canDeletePost && <DeletePostButton postId={post.id} />}
    </article>
  );
}
