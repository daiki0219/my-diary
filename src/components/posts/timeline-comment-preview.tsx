import type { TimelineCommentPreview as TimelineCommentPreviewData } from "@/lib/comment-data";

export function TimelineCommentPreview({
  comments,
}: {
  comments: readonly TimelineCommentPreviewData[];
}) {
  if (comments.length === 0) {
    return null;
  }

  return (
    <div className="mt-4 min-w-0 border-t border-border-subtle/70 pt-3">
      <p className="text-xs font-semibold text-text-muted">最新のコメント</p>
      <ol aria-label="最新のコメント" className="mt-2 min-w-0 space-y-2.5">
        {comments.map((comment) => (
          <li className="min-w-0" key={comment.id}>
            <p className="break-words text-xs font-semibold text-text-primary [overflow-wrap:anywhere]">
              {comment.authorUsername}
            </p>
            <p className="mt-0.5 line-clamp-2 whitespace-pre-wrap break-words text-sm leading-5 text-text-secondary [overflow-wrap:anywhere]">
              {comment.body}
            </p>
          </li>
        ))}
      </ol>
    </div>
  );
}
