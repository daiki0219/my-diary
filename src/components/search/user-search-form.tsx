"use client";

import { FormEvent, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

import { USER_SEARCH_MAX_LENGTH } from "@/lib/user-search-data";

type UserSearchFormProps = {
  initialQuery: string;
};

export function UserSearchForm({ initialQuery }: UserSearchFormProps) {
  const router = useRouter();
  const [query, setQuery] = useState(initialQuery);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedQuery = query.trim();
    const length = Array.from(normalizedQuery).length;

    if (length < 1) {
      setError("ユーザー名を入力してください。");
      return;
    }

    if (length > USER_SEARCH_MAX_LENGTH) {
      setError(
        `検索語は${USER_SEARCH_MAX_LENGTH}文字以下で入力してください。`,
      );
      return;
    }

    setError(null);
    startTransition(() => {
      router.push(`/search?q=${encodeURIComponent(normalizedQuery)}`);
    });
  }

  return (
    <form
      className="rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7"
      onSubmit={handleSubmit}
    >
      <label
        className="block text-sm font-semibold text-stone-700"
        htmlFor="user-search-query"
      >
        ユーザー名
      </label>
      <input
        aria-describedby={error ? "user-search-error" : undefined}
        className="mt-2 w-full rounded-xl border border-stone-300 bg-white px-4 py-3 text-stone-800 outline-none transition placeholder:text-stone-400 focus:border-orange-500 focus:ring-2 focus:ring-orange-200"
        id="user-search-query"
        maxLength={USER_SEARCH_MAX_LENGTH + 1}
        name="q"
        onChange={(event) => setQuery(event.target.value)}
        placeholder="ユーザー名を入力"
        type="search"
        value={query}
      />
      <div className="mt-2 flex min-w-0 items-start justify-between gap-3">
        <p
          className="min-w-0 text-sm leading-6 text-red-700"
          id="user-search-error"
          role={error ? "alert" : undefined}
        >
          {error}
        </p>
        <p aria-hidden="true" className="shrink-0 text-xs text-stone-500">
          {Array.from(query).length}/{USER_SEARCH_MAX_LENGTH}
        </p>
      </div>
      <button
        aria-disabled={isPending}
        className="mt-4 w-full rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 disabled:cursor-not-allowed disabled:opacity-60"
        disabled={isPending}
        type="submit"
      >
        {isPending ? "検索中…" : "検索する"}
      </button>
    </form>
  );
}
