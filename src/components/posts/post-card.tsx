import Link from "next/link";

import { CommentCount } from "@/components/posts/comment-count";
import { DeletePostButton } from "@/components/posts/delete-post-button";
import { PostImageGallery } from "@/components/posts/post-image-gallery";
import { PostLocation } from "@/components/posts/post-location";
import { ReactionControls } from "@/components/posts/reaction-controls";
import { TagList } from "@/components/posts/tag-list";
import { Surface } from "@/components/ui/surface";
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
  headingAs = "h2",
  post,
}: {
  canDeletePost: boolean;
  headingAs?: "h2" | "h3";
  post: Post;
}) {
  const createdAt = new Date(post.created_at);
  const Heading = headingAs;

  return (
    <Surface
      as="article"
      className="min-w-0 border border-border-subtle/70 p-4 shadow-surface sm:p-5"
      variant="elevated"
    >
      <div className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-muted">
        <time dateTime={post.created_at}>{dateFormatter.format(createdAt)}</time>
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

      {post.title && (
        <Heading className="mt-3 break-words font-brand text-xl font-medium leading-8 tracking-[0.01em] text-text-primary [overflow-wrap:anywhere]">
          {post.title}
        </Heading>
      )}

      {post.images.length > 0 && (
        <div className="[&>ol]:!mt-4">
          <PostImageGallery images={post.images} />
        </div>
      )}

      <PostLocation locationName={post.location_name} variant="timeline" />

      <p className="mt-2.5 whitespace-pre-wrap break-words text-[15px] leading-7 text-text-secondary [overflow-wrap:anywhere]">
        {post.body}
      </p>

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

      {canDeletePost && <DeletePostButton postId={post.id} />}
    </Surface>
  );
}
