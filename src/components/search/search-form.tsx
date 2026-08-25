import { Button } from "@/components/ui/actions";
import {
  SEARCH_QUERY_MAX_LENGTH,
  type SearchCategory,
} from "@/lib/search-query";

const formContent: Record<
  SearchCategory,
  { label: string; description: string; placeholder: string }
> = {
  users: {
    label: "ユーザー名",
    description: "ユーザー名の一部を入力してください。",
    placeholder: "ユーザー名を入力",
  },
  tags: {
    label: "タグ名",
    description: "タグ名の一部を入力してください。先頭の#は省略できます。",
    placeholder: "タグ名を入力",
  },
  posts: {
    label: "投稿タイトル・本文",
    description: "閲覧できる日記のタイトルまたは本文の一部を入力してください。",
    placeholder: "タイトル・本文を入力",
  },
};

export function SearchForm({
  category,
  initialQuery,
  error,
}: {
  category: SearchCategory;
  initialQuery: string;
  error: string | null;
}) {
  const content = formContent[category];
  const descriptionId = "search-query-description";
  const errorId = "search-query-error";

  return (
    <form action="/search" method="get">
      <input name="category" type="hidden" value={category} />
      <label
        className="block text-sm font-semibold text-text-primary"
        htmlFor="search-query"
      >
        {content.label}
      </label>
      <p
        className="mt-1 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]"
        id={descriptionId}
      >
        {content.description}
      </p>
      <div className="mt-3 flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start">
        <div className="min-w-0 flex-1">
          <input
            aria-describedby={
              error ? `${descriptionId} ${errorId}` : descriptionId
            }
            aria-invalid={error ? true : undefined}
            className="min-h-11 w-full min-w-0 rounded-control border border-border-control bg-surface-elevated px-4 py-3 text-base text-text-primary outline-none transition placeholder:text-text-muted focus:border-brand-primary focus:ring-2 focus:ring-brand-soft"
            defaultValue={initialQuery}
            id="search-query"
            maxLength={SEARCH_QUERY_MAX_LENGTH[category] * 2}
            name="q"
            placeholder={content.placeholder}
            type="search"
          />
          {error && (
            <p
              className="mt-2 break-words text-sm leading-6 text-danger [overflow-wrap:anywhere]"
              id={errorId}
              role="alert"
            >
              {error}
            </p>
          )}
        </div>
        <Button
          className="w-full shrink-0 sm:w-auto"
          type="submit"
          variant="primary"
        >
          検索する
        </Button>
      </div>
    </form>
  );
}
