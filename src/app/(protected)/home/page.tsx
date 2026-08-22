import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";

import { logout } from "@/app/auth/actions";
import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import { ActionLink, Button } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import {
  SegmentedNav,
  SegmentedNavLink,
} from "@/components/ui/segmented-nav";
import { Surface } from "@/components/ui/surface";
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
        <Surface className="p-5 shadow-surface sm:p-7" variant="muted">
          <p className="text-sm font-medium text-brand-primary-hover">
            みんなの新しい記録
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-text-primary">
            タイムライン
          </h1>
          <p className="mt-3 text-sm leading-6 text-text-secondary">
            あなたが閲覧できる日記を、新しい順に表示します。
          </p>
          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <ActionLink
              href="/posts/new"
              variant="primary"
            >
              日記を書く
            </ActionLink>
            <ActionLink
              href="/profile/posts"
              variant="secondary"
            >
              自分の日記
            </ActionLink>
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
            className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
            href="/exchange"
          >
            交換日記
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
                <span className="shrink-0 rounded-full bg-orange-700 px-2.5 py-0.5 text-xs font-bold text-white">
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
        </Surface>

        <SegmentedNav aria-label="タイムラインの種類" className="mt-5">
          <SegmentedNavLink
            href="/home?feed=following"
            isCurrent={feed === "following"}
          >
            フォロー中
          </SegmentedNavLink>
          <SegmentedNavLink
            href="/home?feed=latest"
            isCurrent={feed === "latest"}
          >
            最新投稿
          </SegmentedNavLink>
        </SegmentedNav>
        <p className="mt-3 text-sm leading-6 text-stone-600">
          {currentFeedContent.description}
        </p>

        {params.error === "logout-failed" && (
          <FeedbackPanel
            className="mt-5"
            role="alert"
            variant="error"
          >
            ログアウトに失敗しました。時間をおいてもう一度お試しください。
          </FeedbackPanel>
        )}

        {postsError ? (
          <FeedbackPanel
            className="mt-5"
            role="alert"
            title="タイムラインを読み込めませんでした"
            variant="error"
          >
            時間をおいて、もう一度お試しください。
          </FeedbackPanel>
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
              <Pagination
                aria-label="タイムラインのページ移動"
                className="mt-6"
              >
                <PaginationLink
                  className="w-full"
                  href={`/home?feed=${feed}&cursor=${encodeURIComponent(nextCursor)}`}
                >
                  <span>次の投稿を見る</span>
                  <span aria-hidden="true">→</span>
                </PaginationLink>
              </Pagination>
            )}
            {!nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-stone-500">
                現在表示できる投稿をすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <EmptyState
            action={
              <ActionLink href={`/home?feed=${feed}`} variant="neutral">
                最初のページへ戻る
              </ActionLink>
            }
            className="mt-5"
            description="フォロー関係や公開範囲が変更された可能性があります。"
            title="現在表示できる投稿はありません"
          />
        ) : (
          <EmptyState
            action={
              <ActionLink href="/posts/new" variant="secondary">
                日記を書く
              </ActionLink>
            }
            className="mt-5"
            decoration={
              <Image
                alt=""
                aria-hidden="true"
                className="mx-auto h-auto w-14 opacity-70"
                height={60}
                src="/images/brand/diary-sprig.png"
                width={56}
              />
            }
            description={currentFeedContent.emptyDescription}
            title={currentFeedContent.emptyTitle}
          />
        )}

        <form action={logout} className="mt-8">
          <Button className="w-full" type="submit" variant="quiet">
            ログアウト
          </Button>
        </form>
      </div>
    </section>
  );
}
