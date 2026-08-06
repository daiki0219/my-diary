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
    <form
      action="/search"
      className="rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7"
      method="get"
    >
      <input name="category" type="hidden" value={category} />
      <label
        className="block text-sm font-semibold text-stone-700"
        htmlFor="search-query"
      >
        {content.label}
      </label>
      <p className="mt-1 text-sm leading-6 text-stone-500" id={descriptionId}>
        {content.description}
      </p>
      <input
        aria-describedby={error ? `${descriptionId} ${errorId}` : descriptionId}
        aria-invalid={error ? true : undefined}
        className="mt-2 w-full min-w-0 rounded-xl border border-stone-300 bg-white px-4 py-3 text-stone-800 outline-none transition placeholder:text-stone-400 focus:border-orange-500 focus:ring-2 focus:ring-orange-200"
        defaultValue={initialQuery}
        id="search-query"
        maxLength={SEARCH_QUERY_MAX_LENGTH[category] * 2}
        name="q"
        placeholder={content.placeholder}
        type="search"
      />
      {error && (
        <p
          className="mt-2 text-sm leading-6 text-red-700"
          id={errorId}
          role="alert"
        >
          {error}
        </p>
      )}
      <button
        className="mt-4 w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
        type="submit"
      >
        検索する
      </button>
    </form>
  );
}
