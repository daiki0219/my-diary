import Link from "next/link";

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
      <div className="rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
        <h2 className="text-lg font-bold text-stone-800">
          {cursor
            ? "次のタグはありません"
            : "該当するタグが見つかりませんでした"}
        </h2>
        <p className="mt-2 text-sm leading-6 text-stone-500">
          {cursor
            ? "この検索結果は最後まで表示されています。"
            : "別のタグ名でもう一度お試しください。"}
        </p>
        {cursor && (
          <Link
            className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={buildSearchUrl({ category: "tags", query })}
          >
            最初から検索する
          </Link>
        )}
      </div>
    );
  }

  return (
    <section aria-labelledby="tag-search-results-heading">
      <h2
        className="text-lg font-bold text-stone-800"
        id="tag-search-results-heading"
      >
        検索結果
      </h2>
      <ul
        aria-label="タグ検索結果"
        className="mt-3 grid min-w-0 gap-3 sm:grid-cols-2"
      >
        {tags.map((tag) => (
          <li className="min-w-0" key={tag.id}>
            <Link
              className="flex min-h-11 min-w-0 items-center rounded-2xl border border-stone-200 bg-white px-4 py-3 font-semibold text-orange-900 shadow-sm underline-offset-4 transition hover:border-orange-300 hover:bg-orange-50 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={`/tags/${tag.id}`}
            >
              <span className="min-w-0 break-words [overflow-wrap:anywhere]">
                #{tag.name}
              </span>
            </Link>
          </li>
        ))}
      </ul>

      {nextCursor && (
        <nav aria-label="タグ検索結果のページ移動" className="mt-6">
          <Link
            className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={buildSearchUrl({
              category: "tags",
              query,
              cursor: nextCursor,
            })}
          >
            次のタグを見る →
          </Link>
        </nav>
      )}

      {!nextCursor && cursor && (
        <p className="mt-6 text-center text-sm text-stone-500">
          検索結果をすべて表示しました。
        </p>
      )}
    </section>
  );
}
