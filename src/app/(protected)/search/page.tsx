import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { UserSearchForm } from "@/components/search/user-search-form";
import { UserSearchResults } from "@/components/search/user-search-results";
import { createClient } from "@/lib/supabase/server";
import {
  searchUsers,
  USER_SEARCH_MAX_LENGTH,
} from "@/lib/user-search-data";

export const metadata: Metadata = {
  title: "ユーザー検索",
};

type SearchPageProps = {
  searchParams: Promise<{
    q?: string | string[];
  }>;
};

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const params = await searchParams;
  const rawQuery = typeof params.q === "string" ? params.q : "";
  const query = rawQuery.trim();
  const queryLength = Array.from(query).length;
  const validationError =
    queryLength > USER_SEARCH_MAX_LENGTH
      ? `検索語は${USER_SEARCH_MAX_LENGTH}文字以下で入力してください。`
      : null;
  const result =
    queryLength > 0 && !validationError
      ? await searchUsers(supabase, query)
      : null;

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ← ホームへ戻る
        </Link>

        <div className="mt-5">
          <p className="text-sm font-medium text-orange-700">
            ゆるくつながる
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            ユーザーを探す
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            ユーザー名の一部を入力して検索できます。
          </p>
        </div>

        <div className="mt-5">
          <UserSearchForm initialQuery={rawQuery} />
        </div>

        <div className="mt-5">
          {validationError ? (
            <p
              className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
              role="alert"
            >
              {validationError}
            </p>
          ) : !query ? (
            <div className="rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
              <h2 className="text-lg font-bold text-stone-800">
                ユーザー名を入力して検索してください
              </h2>
            </div>
          ) : result?.status === "error" ? (
            <p
              className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
              role="alert"
            >
              ユーザーを検索できませんでした。時間をおいてもう一度お試しください。
            </p>
          ) : (
            <UserSearchResults
              currentUserId={currentUserId}
              results={result?.data ?? []}
            />
          )}
        </div>
      </div>
    </section>
  );
}
