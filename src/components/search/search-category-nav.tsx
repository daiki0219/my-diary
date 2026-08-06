import Link from "next/link";

import {
  buildSearchUrl,
  type SearchCategory,
} from "@/lib/search-query";

const categoryLabels: Record<SearchCategory, string> = {
  users: "ユーザー",
  tags: "タグ",
};

export function SearchCategoryNav({
  activeCategory,
  query,
}: {
  activeCategory: SearchCategory | null;
  query: string;
}) {
  return (
    <nav
      aria-label="検索カテゴリ"
      className="grid min-w-0 grid-cols-2 gap-1 rounded-2xl bg-stone-100 p-1"
    >
      {(Object.keys(categoryLabels) as SearchCategory[]).map((category) => (
        <Link
          aria-current={activeCategory === category ? "page" : undefined}
          className={`min-w-0 rounded-xl px-3 py-2.5 text-center text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 ${
            activeCategory === category
              ? "bg-white text-orange-800 shadow-sm"
              : "text-stone-600 hover:bg-white/70 hover:text-stone-800"
          }`}
          href={buildSearchUrl({ category, query })}
          key={category}
        >
          {categoryLabels[category]}
        </Link>
      ))}
    </nav>
  );
}
