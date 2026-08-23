import { CommentForm } from "@/components/posts/comment-form";
import { CommentThreadList } from "@/components/posts/comment-thread-list";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { buildCommentThreads, type Comment } from "@/lib/comment-data";

export function CommentList({
  comments,
  currentUserId,
  error,
  isTruncated,
  postId,
  total,
}: {
  comments: Comment[] | null;
  currentUserId: string;
  error: boolean;
  isTruncated: boolean;
  postId: string;
  total: number | null;
}) {
  return (
    <section
      aria-labelledby="comments-heading"
      className="mt-8 min-w-0 border-t border-border-subtle/70 pt-7 sm:mt-10 sm:pt-8"
    >
      <div className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
        <h2
          className="text-xl font-semibold text-text-primary"
          id="comments-heading"
        >
          コメント
        </h2>
        {total !== null && (
          <p className="text-sm font-medium text-text-muted">{total}件</p>
        )}
      </div>

      <CommentForm postId={postId} />

      {error || !comments ? (
        <FeedbackPanel
          className="mt-6"
          role="alert"
          variant="error"
        >
          コメントを読み込めませんでした。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      ) : comments.length > 0 ? (
        <>
          <CommentThreadList
            currentUserId={currentUserId}
            postId={postId}
            threads={buildCommentThreads(comments)}
          />
          {isTruncated && (
            <p className="mt-5 text-sm leading-6 text-text-muted">
              コメントが多いため、古い順に100件を表示しています。
            </p>
          )}
        </>
      ) : (
        <p className="mt-6 text-sm leading-6 text-text-secondary">
          まだコメントはありません。感じたことを気軽に残してみましょう。
        </p>
      )}
    </section>
  );
}
