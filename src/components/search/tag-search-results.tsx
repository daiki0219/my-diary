import { DiscoveryTagList } from "@/components/tags/discovery-tag-list";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import { buildSearchUrl } from "@/lib/search-query";
import type { TagSearchResultRow } from "@/lib/tag-search-data";

export function TagSearchResults({
  query,
  cursor,
  tags,
  nextCursor,
}: {
  query: string;
  cursor: string | null;
  tags: TagSearchResultRow[];
  nextCursor: string | null;
}) {
  if (tags.length === 0) {
    return (
      <EmptyState
        action={
          cursor ? (
            <ActionLink
              href={buildSearchUrl({ category: "tags", query })}
              variant="neutral"
            >
              最初から検索する
            </ActionLink>
          ) : undefined
        }
        description={
          cursor
            ? "この検索結果は最後まで表示されています。"
            : "別のタグ名でもう一度お試しください。"
        }
        title={
          cursor
            ? "次のタグはありません"
            : "該当するタグが見つかりませんでした"
        }
      />
    );
  }

  return (
    <section aria-labelledby="tag-search-results-heading">
      <h2
        className="text-lg font-semibold text-text-primary"
        id="tag-search-results-heading"
      >
        検索結果
      </h2>
      <DiscoveryTagList
        ariaLabel="タグ検索結果"
        className="mt-3"
        tags={tags}
      />

      {nextCursor && (
        <Pagination aria-label="タグ検索結果のページ移動" className="mt-6">
          <PaginationLink
            className="w-full"
            href={buildSearchUrl({
              category: "tags",
              query,
              cursor: nextCursor,
            })}
          >
            <span>次のタグを見る</span>
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
