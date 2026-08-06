import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { SearchCategoryNav } from "@/components/search/search-category-nav";
import { SearchForm } from "@/components/search/search-form";
import { TagSearchResults } from "@/components/search/tag-search-results";
import { UserSearchResults } from "@/components/search/user-search-results";
import { decodeTagSearchCursor } from "@/lib/search-cursor";
import {
  buildSearchUrl,
  isSearchCategory,
  readSingleQueryParam,
  type SearchCategory,
  validateSearchQuery,
} from "@/lib/search-query";
import { createClient } from "@/lib/supabase/server";
import { searchTags } from "@/lib/tag-search-data";
import { searchUsers } from "@/lib/user-search-data";

export const metadata: Metadata = {
  title: "検索",
};

type SearchPageProps = {
  searchParams: Promise<{
    category?: string | string[];
    q?: string | string[];
    cursor?: string | string[];
  }>;
};

const MULTIPLE_QUERY_ERROR =
  "検索URLに同じ項目が複数含まれています。URLを確認して、最初から検索してください。";

export default async function SearchPage({ searchParams }: SearchPageProps) {
  const supabase = await createClient();
  const [{ data: claimsData, error: claimsError }, params] = await Promise.all([
    supabase.auth.getClaims(),
    searchParams,
  ]);
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const categoryParam = readSingleQueryParam(params.category);
  const queryParam = readSingleQueryParam(params.q);
  const cursorParam = readSingleQueryParam(params.cursor);
  const hasMultipleParam = [categoryParam, queryParam, cursorParam].some(
    (param) => param.status === "multiple",
  );

  let category: SearchCategory | null = null;
  let pageError: string | null = hasMultipleParam
    ? MULTIPLE_QUERY_ERROR
    : null;

  if (!pageError && categoryParam.status === "valid") {
    if (isSearchCategory(categoryParam.value)) {
      category = categoryParam.value;
    } else {
      pageError =
        "検索カテゴリを確認できませんでした。ユーザーまたはタグを選んでください。";
    }
  } else if (!pageError && categoryParam.status === "missing") {
    category = "users";
  }

  const formCategory = category ?? "users";
  const rawQuery = queryParam.status === "valid" ? queryParam.value : "";
  const queryValidation = validateSearchQuery(formCategory, rawQuery);
  const canonicalQuery = queryValidation.query;
  const rawCursor = cursorParam.status === "valid" ? cursorParam.value : null;
  let tagCursor: ReturnType<typeof decodeTagSearchCursor> = null;

  if (!pageError && category === "users" && rawCursor !== null) {
    pageError = "ユーザー検索ではページ情報を使用できません。";
  }

  if (!pageError && category === "tags" && rawCursor !== null) {
    tagCursor =
      queryValidation.error === null && !queryValidation.isEmpty
        ? decodeTagSearchCursor(rawCursor, canonicalQuery)
        : null;

    if (!tagCursor) {
      pageError =
        "タグ検索のページ情報を確認できませんでした。最初から検索してください。";
    }
  }

  const canRedirectToCanonicalQuery = queryValidation.error === null;

  if (
    !pageError &&
    category &&
    canRedirectToCanonicalQuery &&
    (categoryParam.status === "missing" ||
      (queryParam.status === "valid" &&
        (rawQuery !== canonicalQuery || canonicalQuery === "")))
  ) {
    redirect(
      buildSearchUrl({
        category,
        query: canonicalQuery,
        cursor: rawCursor ?? undefined,
      }),
    );
  }

  const canSearch =
    !pageError &&
    queryValidation.error === null &&
    !queryValidation.isEmpty;
  const userResult =
    canSearch && category === "users"
      ? await searchUsers(supabase, canonicalQuery)
      : null;
  const tagResult =
    canSearch && category === "tags"
      ? await searchTags(
          supabase,
          canonicalQuery,
          tagCursor?.afterNormalizedName ?? null,
        )
      : null;
  const navigationQuery =
    queryValidation.error === null ? canonicalQuery : "";

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ← ホームへ戻る
        </Link>

        <div className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">
            ゆるく見つける
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            検索
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            ユーザー名や、閲覧できる日記で使われているタグを探せます。
          </p>
        </div>

        <div className="mt-5">
          <SearchCategoryNav
            activeCategory={pageError && !category ? null : category}
            query={navigationQuery}
          />
        </div>

        <div className="mt-5">
          <SearchForm
            category={formCategory}
            error={pageError ? null : queryValidation.error}
            initialQuery={rawQuery}
          />
        </div>

        <div className="mt-5">
          {pageError ? (
            <div className="rounded-3xl border border-red-200 bg-red-50 p-5">
              <h2 className="font-semibold text-stone-800">
                検索URLを確認してください
              </h2>
              <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
                {pageError}
              </p>
              <Link
                className="mt-5 inline-flex min-h-10 items-center rounded-full border border-red-300 bg-white px-5 py-2 text-sm font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
                href={buildSearchUrl({
                  category: category ?? "users",
                  query:
                    category && queryValidation.error === null
                      ? canonicalQuery
                      : undefined,
                })}
              >
                最初から検索する
              </Link>
            </div>
          ) : queryValidation.error ? null : queryValidation.isEmpty ? (
            <div className="rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
              <h2 className="text-lg font-bold text-stone-800">
                {category === "tags"
                  ? "タグ名を入力して検索してください"
                  : "ユーザー名を入力して検索してください"}
              </h2>
            </div>
          ) : userResult?.status === "error" ? (
            <p
              className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
              role="alert"
            >
              ユーザーを検索できませんでした。時間をおいてもう一度お試しください。
            </p>
          ) : userResult?.status === "success" ? (
            <UserSearchResults
              currentUserId={currentUserId}
              results={userResult.data}
            />
          ) : tagResult?.error ? (
            <p
              className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
              role="alert"
            >
              タグを検索できませんでした。時間をおいてもう一度お試しください。
            </p>
          ) : tagResult?.data ? (
            <TagSearchResults
              cursor={rawCursor}
              nextCursor={tagResult.nextCursor}
              query={canonicalQuery}
              tags={tagResult.data}
            />
          ) : null}
        </div>
      </div>
    </section>
  );
}
