import type { Metadata } from "next";
import Image from "next/image";
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
  const postsResult = hasInvalidCursor
    ? {
        data: null,
        nextCursor: null,
        error: new Error("Invalid timeline cursor."),
        reactionsError: null,
        commentsError: null,
      }
    : await getTimelinePosts(supabase, userId, feed, cursor);
  const { data: posts, error: postsError } = postsResult;
  const nextCursor = postsResult.nextCursor;
  const currentFeedContent = feedContent[feed];

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Surface className="overflow-hidden p-5 sm:p-7" variant="muted">
          <div className="flex min-w-0 items-start gap-3 sm:gap-5">
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-brand-primary-hover">
                今日のホーム
              </p>
              <h1 className="mt-2 break-words text-3xl font-semibold tracking-tight text-text-primary [overflow-wrap:anywhere]">
                今日も、ゆるく残してみよう
              </h1>
              <p className="mt-3 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
                書きたいことを気軽に残して、みんなの日記もゆっくり読めます。
              </p>
            </div>
            <Image
              alt=""
              aria-hidden="true"
              className="h-auto w-14 shrink-0 opacity-70 sm:w-16"
              height={72}
              priority
              src="/images/brand/diary-sprig.png"
              width={64}
            />
          </div>
          <div className="mt-5">
            <ActionLink
              className="w-full"
              href="/posts/new"
              variant="primary"
            >
              日記を書く
            </ActionLink>
          </div>
        </Surface>

        <p className="mt-6 text-sm font-medium text-brand-primary-hover">
          日記を読む
        </p>
        <SegmentedNav aria-label="タイムラインの種類" className="mt-3">
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
            description={currentFeedContent.emptyDescription}
            title={currentFeedContent.emptyTitle}
          />
        )}

        <nav
          aria-label="その他のメニュー"
          className="mt-10 border-t border-border-subtle pt-6"
        >
          <p className="text-sm font-medium text-text-muted">
            そのほかのメニュー
          </p>
          <ul className="mt-2 grid min-w-0 grid-cols-2 gap-1">
            {[
              { href: "/profile/posts", label: "自分の日記" },
              { href: "/search", label: "検索" },
              { href: "/exchange", label: "交換日記" },
              { href: "/tags", label: "タグ" },
              { href: "/settings", label: "設定" },
            ].map((item) => (
              <li className="min-w-0" key={item.href}>
                <ActionLink
                  className="w-full min-w-0 justify-start break-words [overflow-wrap:anywhere]"
                  href={item.href}
                  variant="quiet"
                >
                  {item.label}
                </ActionLink>
              </li>
            ))}
          </ul>
        </nav>

        <form
          action={logout}
          className="mt-4 border-t border-border-subtle pt-4"
        >
          <Button className="w-full" type="submit" variant="quiet">
            ログアウト
          </Button>
        </form>
      </div>
    </section>
  );
}
