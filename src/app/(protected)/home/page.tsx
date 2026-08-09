import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { logout } from "@/app/auth/actions";
import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import {
  getTimelinePosts,
  type TimelineFeed,
} from "@/lib/post-data";
import { getUnreadNotificationCount } from "@/lib/notification-data";
import { createClient } from "@/lib/supabase/server";
import { decodeTimelineCursor } from "@/lib/timeline-cursor";

export const metadata: Metadata = {
  title: "タイムライン",
};

type HomePageProps = {
  searchParams: Promise<{
    error?: string | string[];
    feed?: string | string[];
    cursor?: string | string[];
  }>;
};

const feedContent: Record<
  TimelineFeed,
  { description: string; emptyTitle: string; emptyDescription: string }
> = {
  following: {
    description:
      "自分とフォロー中のユーザーの日記を、新しい順に表示します。",
    emptyTitle: "自分やフォロー中のユーザーの投稿がまだありません。",
    emptyDescription:
      "日記を書いたり、気になるユーザーをフォローしてみましょう。",
  },
  latest: {
    description: "公開されているみんなの日記を、新しい順に表示します。",
    emptyTitle: "公開されている投稿がまだありません。",
    emptyDescription: "最初の公開日記を書いてみませんか。",
  },
};

function getTimelineFeed(feed: string | string[] | undefined): TimelineFeed {
  return feed === "latest" ? "latest" : "following";
}

export default async function HomePage({ searchParams }: HomePageProps) {
  const supabase = await createClient();
  const [{ data, error }, params] = await Promise.all([
    supabase.auth.getClaims(),
    searchParams,
  ]);
  const userId = data?.claims?.sub;

  if (error || !userId) {
    redirect("/login");
  }

  const feed = getTimelineFeed(params.feed);
  const rawCursor = params.cursor;
  const cursor =
    typeof rawCursor === "string"
      ? decodeTimelineCursor(rawCursor, feed)
      : null;
  const hasInvalidCursor =
    rawCursor !== undefined &&
    (typeof rawCursor !== "string" || cursor === null);
  const [postsResult, unreadNotificationsResult] = await Promise.all([
    hasInvalidCursor
      ? Promise.resolve({
          data: null,
          nextCursor: null,
          error: new Error("Invalid timeline cursor."),
          reactionsError: null,
          commentsError: null,
        })
      : getTimelinePosts(supabase, userId, feed, cursor),
    getUnreadNotificationCount(supabase),
  ]);
  const { data: posts, error: postsError } = postsResult;
  const nextCursor = postsResult.nextCursor;
  const unreadNotificationCount = unreadNotificationsResult.count;
  const currentFeedContent = feedContent[feed];

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <div className="rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">
            みんなの新しい記録
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            タイムライン
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            あなたが閲覧できる日記を、新しい順に表示します。
          </p>
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <Link
              className="rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/posts/new"
            >
              日記を書く
            </Link>
            <Link
              className="rounded-full border border-orange-300 bg-white px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/profile/posts"
            >
              自分の日記
            </Link>
          </div>
          <Link
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/profile"
          >
            プロフィール
          </Link>
          <Link
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/calendar"
          >
            カレンダーで振り返る
          </Link>
          <Link
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/search"
          >
            ユーザー・タグ・投稿を探す
          </Link>
          <Link
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/tags"
          >
            タグから日記を探す
          </Link>
          <Link
            aria-label={
              unreadNotificationCount !== null && unreadNotificationCount > 0
                ? `通知、未読${unreadNotificationCount.toLocaleString("ja-JP")}件`
                : "通知"
            }
            className="mt-3 flex min-w-0 items-center justify-center gap-2 rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/notifications"
          >
            <span>通知</span>
            {unreadNotificationCount !== null &&
              unreadNotificationCount > 0 && (
                <span className="shrink-0 rounded-full bg-orange-600 px-2.5 py-0.5 text-xs font-bold text-white">
                  未読 {unreadNotificationCount > 99 ? "99+" : unreadNotificationCount}
                </span>
              )}
          </Link>
          <Link
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/settings"
          >
            設定
          </Link>
        </div>

        <nav
          aria-label="タイムラインの種類"
          className="mt-5 grid grid-cols-2 gap-1 rounded-2xl bg-stone-100 p-1"
        >
          <Link
            aria-current={feed === "following" ? "page" : undefined}
            className={`min-w-0 rounded-xl px-3 py-2.5 text-center text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 ${
              feed === "following"
                ? "bg-white text-orange-800 shadow-sm"
                : "text-stone-600 hover:bg-white/70 hover:text-stone-800"
            }`}
            href="/home?feed=following"
          >
            フォロー中
          </Link>
          <Link
            aria-current={feed === "latest" ? "page" : undefined}
            className={`min-w-0 rounded-xl px-3 py-2.5 text-center text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 ${
              feed === "latest"
                ? "bg-white text-orange-800 shadow-sm"
                : "text-stone-600 hover:bg-white/70 hover:text-stone-800"
            }`}
            href="/home?feed=latest"
          >
            最新投稿
          </Link>
        </nav>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          {currentFeedContent.description}
        </p>

        {params.error === "logout-failed" && (
          <p
            className="mt-5 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
            role="alert"
          >
            ログアウトに失敗しました。時間をおいてもう一度お試しください。
          </p>
        )}

        {postsError ? (
          <div
            className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5"
            role="alert"
          >
            <h2 className="font-semibold text-stone-800">
              タイムラインを読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : posts && posts.length > 0 ? (
          <>
            <ul aria-label="タイムラインの投稿" className="mt-5 space-y-4">
              {posts.map((post) => (
                <li className="min-w-0" key={post.id}>
                  <TimelinePostCard post={post} showBodyExcerpt />
                </li>
              ))}
            </ul>
            {nextCursor && (
              <nav aria-label="タイムラインのページ移動" className="mt-6">
                <Link
                  className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  href={`/home?feed=${feed}&cursor=${encodeURIComponent(nextCursor)}`}
                >
                  次の投稿を見る →
                </Link>
              </nav>
            )}
            {!nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-stone-500">
                現在表示できる投稿をすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              現在表示できる投稿はありません
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-500">
              フォロー関係や公開範囲が変更された可能性があります。
            </p>
            <Link
              className="mt-5 inline-flex rounded-full border border-orange-300 bg-orange-50 px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={`/home?feed=${feed}`}
            >
              最初のページへ戻る
            </Link>
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              {currentFeedContent.emptyTitle}
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-500">
              {currentFeedContent.emptyDescription}
            </p>
            <Link
              className="mt-5 inline-flex rounded-full border border-orange-300 bg-orange-50 px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/posts/new"
            >
              日記を書く
            </Link>
          </div>
        )}

        <form action={logout} className="mt-8">
          <button
            className="w-full rounded-full border border-stone-300 bg-white px-5 py-3 font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            type="submit"
          >
            ログアウト
          </button>
        </form>
      </div>
    </section>
  );
}
