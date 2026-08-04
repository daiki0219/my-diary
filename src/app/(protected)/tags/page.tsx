import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import {
  decodeTagListCursor,
  getVisibleTags,
} from "@/lib/tag-page-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "タグ一覧",
};

type TagListPageProps = {
  searchParams: Promise<{
    cursor?: string | string[];
  }>;
};

export default async function TagListPage({
  searchParams,
}: TagListPageProps) {
  const supabase = await createClient();
  const [{ data: claimsData, error: claimsError }, query] =
    await Promise.all([supabase.auth.getClaims(), searchParams]);
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const rawCursor = query.cursor;
  const cursor =
    typeof rawCursor === "string" ? decodeTagListCursor(rawCursor) : null;
  const hasInvalidCursor =
    rawCursor !== undefined &&
    (typeof rawCursor !== "string" || cursor === null);

  const result = hasInvalidCursor
    ? null
    : await getVisibleTags(supabase, cursor);

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
            タグから見つける
          </p>
          <h1 className="mt-2 break-words text-3xl font-bold tracking-tight text-stone-800 [overflow-wrap:anywhere]">
            タグ一覧
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            あなたが閲覧できる日記で使われているタグを表示します。
          </p>
        </div>

        {hasInvalidCursor ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              ページ情報を確認できませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              URLを確認するか、タグ一覧の最初からもう一度お試しください。
            </p>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-red-300 bg-white px-5 py-2 text-sm font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
              href="/tags"
            >
              タグ一覧の最初へ戻る
            </Link>
          </div>
        ) : result?.error ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              タグを読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : result?.data && result.data.length > 0 ? (
          <>
            <ul
              aria-label="閲覧できるタグ"
              className="mt-5 grid min-w-0 gap-3 sm:grid-cols-2"
            >
              {result.data.map((tag) => (
                <li className="min-w-0" key={tag.id}>
                  <Link
                    className="flex min-h-11 min-w-0 items-center rounded-2xl border border-stone-200 bg-white px-4 py-3 font-semibold text-orange-900 shadow-sm underline-offset-4 transition hover:border-orange-300 hover:bg-orange-50 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                    href={`/tags/${tag.id}`}
                  >
                    <span className="min-w-0 break-words [overflow-wrap:anywhere]">
                      #{tag.name}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>

            {result.nextCursor && (
              <nav aria-label="タグ一覧のページ移動" className="mt-6">
                <Link
                  className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  href={`/tags?cursor=${encodeURIComponent(result.nextCursor)}`}
                >
                  次のタグを見る →
                </Link>
              </nav>
            )}

            {!result.nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-stone-500">
                閲覧できるタグをすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              次のタグはありません
            </h2>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/tags"
            >
              タグ一覧の最初へ戻る
            </Link>
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              閲覧できるタグはまだありません
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-500">
              投稿にタグが付くと、ここから日記を見つけられます。
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
