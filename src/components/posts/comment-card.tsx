import Link from "next/link";

import { DeleteCommentButton } from "@/components/posts/delete-comment-button";
import type { DisplayComment } from "@/lib/comment-data";

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

export function CommentCard({
  comment,
  currentUserId,
  isReply = false,
  isReplyFormOpen = false,
  onReply,
  postId,
  replyControlsId,
}: {
  comment: DisplayComment;
  currentUserId: string;
  isReply?: boolean;
  isReplyFormOpen?: boolean;
  onReply?: () => void;
  postId: string;
  replyControlsId?: string;
}) {
  const normalizedUsername = comment.author?.username.trim() || "ユーザー";
  const initial = Array.from(normalizedUsername)[0] ?? "人";

  return (
    <article className="min-w-0">
      <div className="flex min-w-0 items-center gap-3">
        <div
          aria-hidden="true"
          className={`flex shrink-0 items-center justify-center rounded-full bg-brand-soft font-semibold text-brand-primary-hover ${
            isReply ? "size-9 text-sm" : "size-10 text-base"
          }`}
        >
          {initial}
        </div>
        <div className="min-w-0">
          <Link
            className="block break-words rounded text-[15px] font-semibold text-text-primary underline-offset-4 [overflow-wrap:anywhere] hover:text-brand-primary-hover hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            href={`/users/${comment.user_id}`}
          >
            {normalizedUsername}
          </Link>
          <time
            className="mt-0.5 block text-xs text-text-muted"
            dateTime={comment.created_at}
          >
            {dateFormatter.format(new Date(comment.created_at))}
          </time>
        </div>
      </div>

      <p className="mt-3 whitespace-pre-wrap break-words text-[15px] leading-[1.7] text-text-primary [overflow-wrap:anywhere]">
        {comment.body}
      </p>

      {(onReply || comment.user_id === currentUserId) && (
        <div className="mt-2 flex min-w-0 flex-wrap items-start gap-x-1">
          {onReply && replyControlsId && (
            <button
              aria-controls={replyControlsId}
              aria-expanded={isReplyFormOpen}
              aria-label={`${normalizedUsername}さんのコメントに返信`}
              className="inline-flex min-h-11 items-center rounded-control px-2 text-sm font-medium text-brand-primary-hover underline-offset-4 hover:bg-brand-soft/60 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
              id={`reply-button-${comment.id}`}
              onClick={onReply}
              type="button"
            >
              返信
            </button>
          )}

          {comment.user_id === currentUserId && (
            <DeleteCommentButton commentId={comment.id} postId={postId} />
          )}
        </div>
      )}
    </article>
  );
}
