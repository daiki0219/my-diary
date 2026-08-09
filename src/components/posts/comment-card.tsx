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
    <article
      className={`min-w-0 rounded-2xl border p-4 ${
        isReply
          ? "border-orange-100 bg-orange-50/40"
          : "border-stone-200 bg-white"
      }`}
    >
      <div className="flex min-w-0 items-center gap-3">
        <div
          aria-hidden="true"
          className="flex size-10 shrink-0 items-center justify-center rounded-full bg-orange-100 text-base font-bold text-orange-800"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <Link
            className="block break-words rounded font-semibold text-stone-800 underline-offset-4 [overflow-wrap:anywhere] hover:text-orange-700 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={`/users/${comment.user_id}`}
          >
            {normalizedUsername}
          </Link>
          <time
            className="mt-0.5 block text-xs text-stone-500"
            dateTime={comment.created_at}
          >
            {dateFormatter.format(new Date(comment.created_at))}
          </time>
        </div>
      </div>

      <p className="mt-3 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
        {comment.body}
      </p>

      {onReply && replyControlsId && (
        <button
          aria-controls={replyControlsId}
          aria-expanded={isReplyFormOpen}
          className="mt-3 rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
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
    </article>
  );
}
