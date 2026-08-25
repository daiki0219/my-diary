import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import type { TimelinePost } from "@/lib/post-data";
import { buildSearchUrl } from "@/lib/search-query";

export function PostSearchResults({
  query,
  cursor,
  posts,
  nextCursor,
}: {
  query: string;
  cursor: string | null;
  posts: TimelinePost[];
  nextCursor: string | null;
}) {
  if (posts.length === 0) {
    return (
      <EmptyState
        action={
          cursor ? (
            <ActionLink
              href={buildSearchUrl({ category: "posts", query })}
              variant="neutral"
            >
              最初から検索する
            </ActionLink>
          ) : undefined
        }
        description={
          cursor
            ? "この検索結果は最後まで表示されています。"
            : "別のタイトルや本文でもう一度お試しください。"
        }
        title={
          cursor
            ? "次の投稿はありません"
            : "該当する投稿が見つかりませんでした"
        }
      />
    );
  }

  return (
    <section aria-labelledby="post-search-results-heading">
      <h2
        className="text-lg font-semibold text-text-primary"
        id="post-search-results-heading"
      >
        検索結果
      </h2>
      <ul aria-label="投稿検索結果" className="mt-3 space-y-4">
        {posts.map((post) => (
          <li className="min-w-0" key={post.id}>
            <TimelinePostCard post={post} />
          </li>
        ))}
      </ul>

      {nextCursor && (
        <Pagination aria-label="投稿検索結果のページ移動" className="mt-6">
          <PaginationLink
            className="w-full"
            href={buildSearchUrl({
              category: "posts",
              query,
              cursor: nextCursor,
            })}
          >
            <span>次の投稿を見る</span>
            <span aria-hidden="true">→</span>
          </PaginationLink>
        </Pagination>
      )}

      {!nextCursor && cursor && (
        <p className="mt-6 text-center text-sm text-text-muted">
          検索結果をすべて表示しました。
        </p>
      )}
    </section>
  );
}
