import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import { isUuid } from "@/lib/profile-data";
import {
  decodeTagPostCursor,
  getVisiblePostsForTag,
  getVisibleTag,
} from "@/lib/tag-page-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "タグの日記",
};

type TagDetailPageProps = {
  params: Promise<{
    tagId: string;
  }>;
  searchParams: Promise<{
    cursor?: string | string[];
  }>;
};

export default async function TagDetailPage({
  params,
  searchParams,
}: TagDetailPageProps) {
  const [{ tagId }, query] = await Promise.all([params, searchParams]);
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  if (!isUuid(tagId)) {
    notFound();
  }

  const rawCursor = query.cursor;
  const cursor =
    typeof rawCursor === "string" ? decodeTagPostCursor(rawCursor) : null;

  if (
    rawCursor !== undefined &&
    (typeof rawCursor !== "string" || cursor === null)
  ) {
    notFound();
  }

  const canonicalTagId = tagId.toLowerCase();

  if (tagId !== canonicalTagId) {
    const canonicalQuery = rawCursor
      ? `?${new URLSearchParams({ cursor: rawCursor }).toString()}`
      : "";
    redirect(`/tags/${canonicalTagId}${canonicalQuery}`);
  }

  const tagResult = await getVisibleTag(supabase, canonicalTagId);

  if (tagResult.error) {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          タグを読み込めませんでした。時間をおいてもう一度お試しください。
        </p>
      </section>
    );
  }

  if (!tagResult.data) {
    notFound();
  }

  const postsResult = await getVisiblePostsForTag(
    supabase,
    canonicalTagId,
    currentUserId,
    cursor,
  );

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/tags"
        >
          ← タグ一覧へ戻る
        </Link>

        <div className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">
            タグが付いた日記
          </p>
          <h1 className="mt-2 break-words text-3xl font-bold tracking-tight text-stone-800 [overflow-wrap:anywhere]">
            #{tagResult.data.name}
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            あなたが閲覧できる日記だけを、新しい順に表示します。
          </p>
        </div>

        {postsResult.error ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              日記を読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : postsResult.data && postsResult.data.length > 0 ? (
          <>
            <div className="mt-5 space-y-4">
              {postsResult.data.map((post) => (
                <TimelinePostCard key={post.id} post={post} />
              ))}
            </div>

            {postsResult.nextCursor && (
              <nav aria-label="タグの日記一覧のページ移動" className="mt-6">
                <Link
                  className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  href={`/tags/${canonicalTagId}?cursor=${encodeURIComponent(postsResult.nextCursor)}`}
                >
                  次の投稿を見る →
                </Link>
              </nav>
            )}

            {!postsResult.nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-stone-500">
                閲覧できる日記をすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              次の投稿はありません
            </h2>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={`/tags/${canonicalTagId}`}
            >
              最初の投稿へ戻る
            </Link>
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              閲覧できる日記はありません
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-500">
              公開範囲が変わった可能性があります。タグ一覧から別のタグも見てみましょう。
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
