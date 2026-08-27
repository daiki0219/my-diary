import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { ExchangeInvitationActions } from "@/components/exchange/exchange-invitation-actions";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import {
  SegmentedNav,
  SegmentedNavLink,
} from "@/components/ui/segmented-nav";
import { Surface } from "@/components/ui/surface";
import {
  getExchangeDiaryListPage,
  getPendingExchangeInvitationsPage,
  type ExchangeDiaryListItem,
  type PendingExchangeInvitation,
} from "@/lib/exchange-data";
import {
  buildExchangeTopQuery,
  parseExchangeTopQuery,
  type ExchangeSearchParams,
} from "@/lib/exchange-query";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "交換日記",
};

type ExchangePageProps = {
  searchParams: Promise<ExchangeSearchParams>;
};

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

const viewCopy = {
  active: {
    description: "相手と続けている日記を、新しく始まった順に表示します。",
    title: "交換中の日記",
  },
  invitations: {
    description: "届いた招待への返事と、送った招待の状況を確認できます。",
    title: "交換日記の招待",
  },
  archived: {
    description: "終了した交換日記も、ふたりの記録として読み返せます。",
    title: "これまでの交換日記",
  },
} as const;

function getCounterpartName(
  counterpart: ExchangeDiaryListItem["counterpart"],
) {
  return counterpart.profile?.username ?? "利用できないユーザー";
}

function getDiaryTitle(item: ExchangeDiaryListItem) {
  if (item.title) {
    return item.title;
  }

  return item.counterpart.profile
    ? `${item.counterpart.profile.username}さんとの交換日記`
    : "交換日記";
}

function DiaryList({
  items,
  view,
}: {
  items: ExchangeDiaryListItem[];
  view: "active" | "archived";
}) {
  return (
    <Surface
      className="mt-4 overflow-hidden border border-border-subtle/70 shadow-surface"
      variant="elevated"
    >
      <ul
        aria-label={view === "active" ? "交換中の交換日記" : "終了した交換日記"}
        className="divide-y divide-border-subtle/70"
      >
        {items.map((item) => {
          const title = getDiaryTitle(item);
          const counterpartName = getCounterpartName(item.counterpart);
          const stateDate =
            view === "active"
              ? item.startedAt
              : (item.archivedAt ?? item.createdAt);

          return (
            <li className="min-w-0 px-4 py-5 sm:px-6" key={item.diaryId}>
              <article className="min-w-0">
                <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
                  <div className="min-w-0">
                    <h3 className="break-words text-lg font-semibold leading-7 text-text-primary [overflow-wrap:anywhere] sm:text-xl">
                      {title}
                    </h3>
                    <p className="mt-1 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
                      {item.counterpart.profile
                        ? `${counterpartName}さんと`
                        : counterpartName}
                    </p>
                  </div>
                  <span
                    className={`inline-flex min-h-7 w-fit shrink-0 items-center gap-2 rounded-full px-3 text-xs font-semibold ${
                      view === "active"
                        ? "bg-success/10 text-success"
                        : "bg-surface-muted text-text-secondary"
                    }`}
                  >
                    <span
                      aria-hidden="true"
                      className={`size-1.5 rounded-full ${
                        view === "active" ? "bg-success" : "bg-text-muted"
                      }`}
                    />
                    {view === "active" ? "交換中" : "終了・閲覧できます"}
                  </span>
                </div>

                <div className="mt-3 flex min-w-0 flex-wrap items-center justify-between gap-x-5 gap-y-2">
                  <p className="break-words text-xs leading-5 text-text-muted [overflow-wrap:anywhere]">
                    {view === "active" ? "開始" : "終了"}：
                    <time dateTime={stateDate}>
                      {dateFormatter.format(new Date(stateDate))}
                    </time>
                  </p>
                  <ActionLink
                    aria-label={`${title}の詳細を見る`}
                    className="-mr-3 max-w-full gap-2 px-3"
                    href={`/exchange/${item.diaryId}`}
                    variant="quiet"
                  >
                    <span>{view === "active" ? "日記を開く" : "記録を読む"}</span>
                    <span aria-hidden="true">→</span>
                  </ActionLink>
                </div>
              </article>
            </li>
          );
        })}
      </ul>
    </Surface>
  );
}

function InvitationList({ items }: { items: PendingExchangeInvitation[] }) {
  return (
    <Surface
      className="mt-4 overflow-hidden border border-border-subtle/70 shadow-surface"
      variant="elevated"
    >
      <ul
        aria-label="現在の交換日記の招待"
        className="divide-y divide-border-subtle/70"
      >
        {items.map((item) => {
          const counterpartName =
            item.counterpartProfile?.username ?? "利用できないユーザー";
          const isReceived = item.direction === "received";

          return (
            <li
              className={`min-w-0 px-4 py-5 sm:px-6 ${
                isReceived ? "bg-brand-soft/20" : "bg-surface-elevated"
              }`}
              key={item.invitationId}
            >
              <article className="min-w-0">
                <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-6">
                  <div className="min-w-0">
                    <h3 className="break-words text-lg font-semibold leading-7 text-text-primary [overflow-wrap:anywhere] sm:text-xl">
                      {counterpartName}
                    </h3>
                    <p className="mt-1 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
                      {isReceived
                        ? "あなたに交換日記の招待が届いています。"
                        : "交換日記へ招待しました。返事を待っています。"}
                    </p>
                  </div>
                  <span
                    className={`inline-flex min-h-7 w-fit shrink-0 items-center gap-1.5 rounded-full px-3 text-xs font-semibold ${
                      isReceived
                        ? "bg-brand-soft text-brand-primary-hover"
                        : "bg-surface-muted text-text-secondary"
                    }`}
                  >
                    <span aria-hidden="true">{isReceived ? "←" : "→"}</span>
                    {isReceived ? "受け取った招待" : "送信した招待"}
                  </span>
                </div>

                <div className="mt-3 flex min-w-0 flex-wrap items-center gap-x-4 gap-y-1">
                  <p className="break-words text-xs leading-5 text-text-muted [overflow-wrap:anywhere]">
                    {isReceived ? "受信" : "送信"}：
                    <time dateTime={item.createdAt}>
                      {dateFormatter.format(new Date(item.createdAt))}
                    </time>
                  </p>
                  {item.counterpartProfile && (
                    <ActionLink
                      className="-ml-3 max-w-full gap-1 px-3 text-sm"
                      href={`/users/${item.counterpartUserId}`}
                      variant="quiet"
                    >
                      プロフィールを見る
                      <span aria-hidden="true">→</span>
                    </ActionLink>
                  )}
                </div>

                <ExchangeInvitationActions
                  counterpartName={counterpartName}
                  direction={item.direction}
                  invitationId={item.invitationId}
                />
              </article>
            </li>
          );
        })}
      </ul>
    </Surface>
  );
}

function NewExchangeGuide() {
  return (
    <Surface
      as="section"
      aria-labelledby="new-exchange-heading"
      className="mt-8 p-5 sm:p-6 xl:mt-0"
      variant="muted"
    >
      <h2
        className="text-base font-semibold text-text-primary"
        id="new-exchange-heading"
      >
        新しい交換日記を始める
      </h2>
      <p className="mt-2 max-w-2xl break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
        フォロー中の人やユーザー検索から相手のプロフィールを開き、交換日記へ招待できます。
      </p>
      <div className="mt-4 flex min-w-0 flex-col gap-2 sm:flex-row sm:flex-wrap xl:flex-col">
        <ActionLink href="/profile/following" variant="secondary">
          フォロー中の人を見る
        </ActionLink>
        <ActionLink href="/search?category=users" variant="neutral">
          ユーザーを検索
        </ActionLink>
      </div>
    </Surface>
  );
}

export default async function ExchangePage({
  searchParams,
}: ExchangePageProps) {
  const supabase = await createClient();
  const [{ data: claimsData, error: claimsError }, params] =
    await Promise.all([supabase.auth.getClaims(), searchParams]);
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const query = parseExchangeTopQuery(params);
  const diaryResult =
    query && query.view !== "invitations"
      ? await getExchangeDiaryListPage(
          supabase,
          currentUserId,
          query.view,
          query.cursor,
        )
      : null;
  const invitationResult =
    query?.view === "invitations"
      ? await getPendingExchangeInvitationsPage(
          supabase,
          currentUserId,
          query.cursor,
        )
      : null;
  const hasLoadError = Boolean(diaryResult?.error || invitationResult?.error);
  const nextCursor = diaryResult?.nextCursor ?? invitationResult?.nextCursor;
  const currentViewCopy = query ? viewCopy[query.view] : null;

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6 lg:py-10">
      <div className="mx-auto min-w-0 w-full max-w-5xl lg:max-w-6xl xl:max-w-none">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>

        <div className="xl:grid xl:grid-cols-[minmax(0,1fr)_18rem] xl:gap-x-8">
          <div className="min-w-0 xl:col-start-1 xl:row-start-1">
            <PageHeader
              className="mt-3"
              description="ふたりで続けている日記と、現在の招待を確認できます。"
              eyebrow="ふたりの記録"
              title="交換日記"
              variant="plain"
            />

            <SegmentedNav aria-label="交換日記の種類" className="mt-5">
              {(
                [
                  ["active", "交換中"],
                  ["invitations", "招待"],
                  ["archived", "終了"],
                ] as const
              ).map(([view, label]) => (
                <SegmentedNavLink
                  className="min-h-11"
                  href={`/exchange?${buildExchangeTopQuery(view)}`}
                  isCurrent={query?.view === view}
                  key={view}
                >
                  {label}
                </SegmentedNavLink>
              ))}
            </SegmentedNav>
          </div>

          <div className="mt-6 min-w-0 xl:col-start-1 xl:row-start-2">
            {currentViewCopy && (
              <div className="min-w-0">
                <h2 className="break-words text-xl font-semibold text-text-primary [overflow-wrap:anywhere] sm:text-2xl">
                  {currentViewCopy.title}
                </h2>
                <p className="mt-1 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
                  {currentViewCopy.description}
                </p>
              </div>
            )}

            {!query ? (
              <FeedbackPanel
                className="mt-4 max-w-3xl"
                role="alert"
                title="ページ情報を確認できませんでした"
                variant="error"
              >
                <p>
                  URLを確認するか、交換日記一覧の最初からもう一度お試しください。
                </p>
                <ActionLink className="mt-4" href="/exchange" variant="neutral">
                  交換日記一覧の最初へ戻る
                </ActionLink>
              </FeedbackPanel>
            ) : hasLoadError ? (
              <FeedbackPanel
                className="mt-4 max-w-3xl"
                role="alert"
                title="交換日記を読み込めませんでした"
                variant="error"
              >
                時間をおいて、もう一度お試しください。
              </FeedbackPanel>
            ) : query.view === "invitations" && invitationResult?.data?.length ? (
              <InvitationList items={invitationResult.data} />
            ) : query.view !== "invitations" && diaryResult?.data?.length ? (
              <DiaryList items={diaryResult.data} view={query.view} />
            ) : query.cursor ? (
              <EmptyState
                action={
                  <ActionLink
                    href={`/exchange?${buildExchangeTopQuery(query.view)}`}
                    variant="neutral"
                  >
                    最初の一覧へ戻る
                  </ActionLink>
                }
                className="mt-4 max-w-3xl"
                title="次の交換日記はありません"
                titleAs="h3"
              />
            ) : (
              <EmptyState
                className="mt-4 max-w-3xl"
                description={
                  query.view === "active"
                    ? "招待が承認されると、ここに交換中の日記が表示されます。"
                    : query.view === "invitations"
                      ? "新しい招待が届いたときや、招待を送ったときにここで確認できます。"
                      : "終了した交換日記は、ここからいつでも読み返せます。"
                }
                title={
                  query.view === "active"
                    ? "交換中の日記はまだありません"
                    : query.view === "invitations"
                      ? "現在の招待はありません"
                      : "終了した交換日記はまだありません"
                }
                titleAs="h3"
              />
            )}

            {query && nextCursor && (
              <Pagination aria-label="交換日記一覧のページ移動" className="mt-6">
                <PaginationLink
                  className="w-full sm:w-auto"
                  href={`/exchange?${buildExchangeTopQuery(query.view, nextCursor)}`}
                >
                  <span>次の20件を見る</span>
                  <span aria-hidden="true">→</span>
                </PaginationLink>
              </Pagination>
            )}

            {query && query.cursor && !nextCursor && !hasLoadError && (
              <p className="mt-6 text-center text-sm text-text-muted">
                現在表示できる交換日記をすべて表示しました。
              </p>
            )}
          </div>

          <aside
            aria-label="新しい交換日記の案内"
            className="min-w-0 xl:col-start-2 xl:row-start-2 xl:mt-6 xl:pt-14"
          >
            <NewExchangeGuide />
          </aside>
        </div>
      </div>
    </section>
  );
}
