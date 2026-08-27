import type { Metadata } from "next";
import Image from "next/image";
import { redirect } from "next/navigation";

import { CalendarSummary } from "@/components/calendar/calendar-summary";
import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import { HomeProfileSummary } from "@/components/profile/home-profile-summary";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import {
  SegmentedNav,
  SegmentedNavLink,
} from "@/components/ui/segmented-nav";
import { getCurrentCalendarSummaryData } from "@/lib/calendar-data";
import {
  getTimelinePosts,
  type TimelineFeed,
} from "@/lib/post-data";
import { getProfileWithCounts } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";
import { decodeTimelineCursor } from "@/lib/timeline-cursor";

export const metadata: Metadata = {
  title: "ホーム",
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
  { emptyTitle: string; emptyDescription: string }
> = {
  following: {
    emptyTitle: "自分やフォロー中のユーザーの投稿がまだありません。",
    emptyDescription:
      "日記を書いたり、気になるユーザーをフォローしてみましょう。",
  },
  latest: {
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
  const calendarSummaryPromise = getCurrentCalendarSummaryData(supabase).catch(
    () => null,
  );
  const profileSummaryPromise = getProfileWithCounts(supabase, userId).catch(
    () => null,
  );
  const postsResult = hasInvalidCursor
    ? {
        data: null,
        nextCursor: null,
        error: new Error("Invalid timeline cursor."),
        reactionsError: null,
        commentsError: null,
        commentPreviews: null,
        commentPreviewsError: null,
      }
    : await getTimelinePosts(supabase, userId, feed, cursor);
  const [calendarSummaryResult, profileSummaryResult] = await Promise.all([
    calendarSummaryPromise,
    profileSummaryPromise,
  ]);
  const { data: posts, error: postsError } = postsResult;
  const commentPreviews = postsResult.commentPreviews;
  const nextCursor = postsResult.nextCursor;
  const currentFeedContent = feedContent[feed];

  return (
    <section className="flex flex-1 px-6 py-3 sm:px-8 sm:py-4 lg:py-10">
      <div className="mx-auto w-full max-w-lg lg:grid lg:max-w-none lg:grid-cols-[minmax(0,1fr)_16rem] lg:items-start lg:gap-8 xl:grid-cols-[minmax(0,1fr)_24rem] xl:gap-10">
        <div className="min-w-0">
          <div className="flex min-w-0 items-center justify-center gap-3 px-1 lg:gap-4">
            <Image
              alt=""
              aria-hidden="true"
              className="h-auto w-9 shrink-0 opacity-80 sm:w-10 lg:w-14"
              height={72}
              priority
              src="/images/brand/diary-sprig.png"
              width={64}
            />
            <h1 className="min-w-0 break-words font-brand text-lg font-medium tracking-wide text-text-primary [overflow-wrap:anywhere] sm:text-xl">
              今日も、ゆるく残してみよう
            </h1>
          </div>

          <ActionLink
            className="mt-2 w-full gap-2 rounded-full shadow-surface lg:mt-4"
            href="/posts/new"
            variant="primary"
          >
            <svg
              aria-hidden="true"
              className="size-5"
              fill="none"
              focusable="false"
              stroke="currentColor"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="1.8"
              viewBox="0 0 24 24"
            >
              <path d="m14 5 5 5M4 20l3.5-.8L19 7.7a2.1 2.1 0 0 0-3-3L4.8 16.2 4 20Z" />
            </svg>
            <span>日記を書く</span>
          </ActionLink>

          <SegmentedNav
            aria-label="タイムラインの種類"
            className="mt-3 lg:mt-6"
          >
            <SegmentedNavLink
              className="min-h-11"
              href="/home?feed=following"
              isCurrent={feed === "following"}
            >
              フォロー中
            </SegmentedNavLink>
            <SegmentedNavLink
              className="min-h-11"
              href="/home?feed=latest"
              isCurrent={feed === "latest"}
            >
              最新
            </SegmentedNavLink>
          </SegmentedNav>

          {params.error === "logout-failed" && (
            <FeedbackPanel
              className="mt-3"
              role="alert"
              variant="error"
            >
              ログアウトに失敗しました。時間をおいてもう一度お試しください。
            </FeedbackPanel>
          )}

          {postsError ? (
            <FeedbackPanel
              className="mt-3"
              role="alert"
              title="タイムラインを読み込めませんでした"
              variant="error"
            >
              時間をおいて、もう一度お試しください。
            </FeedbackPanel>
          ) : posts && posts.length > 0 ? (
            <>
              <ul
                aria-label="タイムラインの投稿"
                className="mt-3 space-y-3 lg:mt-6"
              >
                {posts.map((post) => (
                  <li className="min-w-0" key={post.id}>
                    <TimelinePostCard
                      commentPreview={commentPreviews?.get(post.id) ?? []}
                      post={post}
                    />
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
              className="mt-3"
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
              className="mt-3"
              description={currentFeedContent.emptyDescription}
              title={currentFeedContent.emptyTitle}
            />
          )}

        </div>

        <aside
          aria-label="ホームの補助情報"
          className="hidden space-y-4 lg:block xl:space-y-5"
        >
          {profileSummaryResult?.profile &&
            !profileSummaryResult.profileLoadFailed && (
              <HomeProfileSummary
                counts={profileSummaryResult.counts}
                profile={{
                  bio: profileSummaryResult.profile.bio,
                  username: profileSummaryResult.profile.username,
                }}
              />
            )}
          <CalendarSummary data={calendarSummaryResult?.data ?? null} />
        </aside>
      </div>
    </section>
  );
}
