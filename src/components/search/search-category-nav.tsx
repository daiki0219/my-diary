import {
  SegmentedNav,
  SegmentedNavLink,
} from "@/components/ui/segmented-nav";
import {
  buildSearchUrl,
  type SearchCategory,
} from "@/lib/search-query";

const categoryLabels: Record<SearchCategory, string> = {
  users: "ユーザー",
  tags: "タグ",
  posts: "投稿",
};

export function SearchCategoryNav({
  activeCategory,
  query,
}: {
  activeCategory: SearchCategory | null;
  query: string;
}) {
  return (
    <SegmentedNav aria-label="検索カテゴリ">
      {(Object.keys(categoryLabels) as SearchCategory[]).map((category) => (
        <SegmentedNavLink
          className="min-h-11"
          href={buildSearchUrl({ category, query })}
          isCurrent={activeCategory === category}
          key={category}
        >
          {categoryLabels[category]}
        </SegmentedNavLink>
      ))}
    </SegmentedNav>
  );
}
