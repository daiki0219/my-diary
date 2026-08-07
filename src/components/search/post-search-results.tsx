import Link from "next/link";

import { TimelinePostCard } from "@/components/posts/timeline-post-card";
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
      <div className="rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
        <h2 className="text-lg font-bold text-stone-800">
          {cursor
            ? "次の投稿はありません"
            : "該当する投稿が見つかりませんでした"}
        </h2>
        <p className="mt-2 text-sm leading-6 text-stone-500">
          {cursor
            ? "この検索結果は最後まで表示されています。"
            : "別のタイトルや本文でもう一度お試しください。"}
        </p>
        {cursor && (
          <Link
            className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={buildSearchUrl({ category: "posts", query })}
          >
            最初から検索する
          </Link>
        )}
      </div>
    );
  }

  return (
    <section aria-labelledby="post-search-results-heading">
      <h2
        className="text-lg font-bold text-stone-800"
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
        <nav aria-label="投稿検索結果のページ移動" className="mt-6">
          <Link
            className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={buildSearchUrl({
              category: "posts",
              query,
              cursor: nextCursor,
            })}
          >
            次の投稿を見る →
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
