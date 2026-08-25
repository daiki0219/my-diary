import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { PostSearchResults } from "@/components/search/post-search-results";
import { SearchCategoryNav } from "@/components/search/search-category-nav";
import { SearchForm } from "@/components/search/search-form";
import { TagSearchResults } from "@/components/search/tag-search-results";
import { UserSearchResults } from "@/components/search/user-search-results";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { searchPosts } from "@/lib/post-search-data";
import {
  decodePostSearchCursor,
  decodeTagSearchCursor,
} from "@/lib/search-cursor";
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
        "検索カテゴリを確認できませんでした。ユーザー、タグ、投稿のいずれかを選んでください。";
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
  let postCursor: ReturnType<typeof decodePostSearchCursor> = null;

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

  if (!pageError && category === "posts" && rawCursor !== null) {
    postCursor =
      queryValidation.error === null && !queryValidation.isEmpty
        ? decodePostSearchCursor(rawCursor, canonicalQuery)
        : null;

    if (!postCursor) {
      pageError =
        "投稿検索のページ情報を確認できませんでした。最初から検索してください。";
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
  const postResult =
    canSearch && category === "posts"
      ? await searchPosts(
          supabase,
          canonicalQuery,
          postCursor?.beforeCreatedAt ?? null,
          postCursor?.beforeId ?? null,
          currentUserId,
        )
      : null;
  const navigationQuery =
    queryValidation.error === null ? canonicalQuery : "";
  const hasPostResults =
    category === "posts" && Boolean(postResult?.data?.length);

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>

        <div className="max-w-xl min-w-0">
          <PageHeader
            className="mt-3"
            description="ユーザー名、タグ、閲覧できる日記のタイトル・本文を探せます。"
            eyebrow="ゆるく見つける"
            title="検索"
            variant="plain"
          />

          <div className="mt-5">
            <SearchCategoryNav
              activeCategory={pageError && !category ? null : category}
              query={navigationQuery}
            />
          </div>

          <div className="mt-5 border-t border-border-subtle pt-5">
            <SearchForm
              category={formCategory}
              error={pageError ? null : queryValidation.error}
              initialQuery={rawQuery}
            />
          </div>
        </div>

        <div
          className={`mt-6 min-w-0 ${hasPostResults ? "" : "max-w-xl"}`}
        >
          {pageError ? (
            <FeedbackPanel
              role="alert"
              title="検索URLを確認してください"
              variant="error"
            >
              <p>{pageError}</p>
              <ActionLink
                className="mt-4"
                href={buildSearchUrl({
                  category: category ?? "users",
                  query:
                    category && queryValidation.error === null
                      ? canonicalQuery
                      : undefined,
                })}
                variant="neutral"
              >
                最初から検索する
              </ActionLink>
            </FeedbackPanel>
          ) : queryValidation.error ? null : queryValidation.isEmpty ? (
            <EmptyState
              description="検索語を入力すると、ここに結果が表示されます。"
              title={
                category === "tags"
                  ? "タグ名を入力して検索してください"
                  : category === "posts"
                    ? "投稿タイトル・本文を入力して検索してください"
                    : "ユーザー名を入力して検索してください"
              }
            />
          ) : userResult?.status === "error" ? (
            <FeedbackPanel role="alert" variant="error">
              ユーザーを検索できませんでした。時間をおいてもう一度お試しください。
            </FeedbackPanel>
          ) : userResult?.status === "success" ? (
            <UserSearchResults
              currentUserId={currentUserId}
              results={userResult.data}
            />
          ) : tagResult?.error ? (
            <FeedbackPanel role="alert" variant="error">
              タグを検索できませんでした。時間をおいてもう一度お試しください。
            </FeedbackPanel>
          ) : tagResult?.data ? (
            <TagSearchResults
              cursor={rawCursor}
              nextCursor={tagResult.nextCursor}
              query={canonicalQuery}
              tags={tagResult.data}
            />
          ) : postResult?.error ? (
            <FeedbackPanel role="alert" variant="error">
              投稿を検索できませんでした。時間をおいてもう一度お試しください。
            </FeedbackPanel>
          ) : postResult?.data ? (
            <PostSearchResults
              cursor={rawCursor}
              nextCursor={postResult.nextCursor}
              posts={postResult.data}
              query={canonicalQuery}
            />
          ) : null}
        </div>
      </div>
    </section>
  );
}
