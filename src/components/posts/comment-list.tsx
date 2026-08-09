import { CommentThreadList } from "@/components/posts/comment-thread-list";
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
      className="mt-6 min-w-0 rounded-3xl border border-stone-200 bg-stone-50 p-5 sm:p-6"
    >
      <h2
        className="text-xl font-bold text-stone-800"
        id="comments-heading"
      >
        コメント{total === null ? "" : ` ${total}件`}
      </h2>

      {error || !comments ? (
        <p
          className="mt-4 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm leading-6 text-red-700"
          role="alert"
        >
          コメントを読み込めませんでした。時間をおいてもう一度お試しください。
        </p>
      ) : comments.length > 0 ? (
        <>
          <CommentThreadList
            currentUserId={currentUserId}
            postId={postId}
            threads={buildCommentThreads(comments)}
          />
          {isTruncated && (
            <p className="mt-4 text-sm leading-6 text-stone-600">
              コメントが多いため、古い順に100件を表示しています。
            </p>
          )}
        </>
      ) : (
        <p className="mt-4 text-sm leading-6 text-stone-600">
          まだコメントはありません。感じたことを気軽に残してみましょう。
        </p>
      )}
    </section>
  );
}
