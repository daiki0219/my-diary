import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { ExchangeInvitationActions } from "@/components/exchange/exchange-invitation-actions";
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
    <ul
      aria-label={view === "active" ? "交換中の交換日記" : "終了した交換日記"}
      className="mt-5 min-w-0 space-y-4"
    >
      {items.map((item) => {
        const title = getDiaryTitle(item);
        const counterpartName = getCounterpartName(item.counterpart);

        return (
          <li className="min-w-0" key={item.diaryId}>
            <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
              <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0">
                  <h2 className="break-words text-xl font-bold leading-8 text-stone-800 [overflow-wrap:anywhere]">
                    {title}
                  </h2>
                  <p className="mt-1 min-w-0 break-words text-sm leading-6 text-stone-600 [overflow-wrap:anywhere]">
                    相手：{counterpartName}
                  </p>
                </div>
                <span
                  className={`w-fit shrink-0 rounded-full px-3 py-1 text-xs font-bold ${
                    view === "active"
                      ? "bg-orange-100 text-orange-800"
                      : "bg-stone-100 text-stone-700"
                  }`}
                >
                  {view === "active" ? "交換中" : "終了済み"}
                </span>
              </div>

              <p className="mt-3 text-sm leading-6 text-stone-500">
                {view === "active" ? "開始：" : "終了："}
                <time
                  dateTime={
                    view === "active"
                      ? item.startedAt
                      : (item.archivedAt ?? item.createdAt)
                  }
                >
                  {dateFormatter.format(
                    new Date(
                      view === "active"
                        ? item.startedAt
                        : (item.archivedAt ?? item.createdAt),
                    ),
                  )}
                </time>
              </p>

              <Link
                aria-label={`${title}の詳細を見る`}
                className="mt-5 inline-flex min-h-10 items-center rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
                href={`/exchange/${item.diaryId}`}
              >
                詳細を見る
              </Link>
            </article>
          </li>
        );
      })}
    </ul>
  );
}

function InvitationList({ items }: { items: PendingExchangeInvitation[] }) {
  return (
    <ul aria-label="現在の交換日記の招待" className="mt-5 min-w-0 space-y-4">
      {items.map((item) => {
        const counterpartName =
          item.counterpartProfile?.username ?? "利用できないユーザー";
        const message =
          item.direction === "received"
            ? item.counterpartProfile
              ? `${counterpartName}さんからの招待`
              : `${counterpartName}からの招待`
            : item.counterpartProfile
              ? `${counterpartName}さんの承認待ち`
              : `${counterpartName}の承認待ち`;

        return (
          <li className="min-w-0" key={item.invitationId}>
            <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
              <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <h2 className="min-w-0 break-words text-lg font-bold leading-7 text-stone-800 [overflow-wrap:anywhere]">
                  {message}
                </h2>
                <span className="w-fit shrink-0 rounded-full bg-orange-100 px-3 py-1 text-xs font-bold text-orange-800">
                  {item.direction === "received" ? "招待中" : "承認待ち"}
                </span>
              </div>
              <p className="mt-3 text-sm leading-6 text-stone-500">
                <time dateTime={item.createdAt}>
                  {dateFormatter.format(new Date(item.createdAt))}
                </time>
              </p>
              {item.counterpartProfile && (
                <Link
                  className="mt-3 inline-flex min-h-10 items-center rounded-lg text-sm font-semibold text-orange-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
                  href={`/users/${item.counterpartUserId}`}
                >
                  相手のプロフィールを見る
                </Link>
              )}
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
          <p className="text-sm font-medium text-orange-700">ふたりの記録</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            交換日記
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            参加している交換日記と、現在の招待を確認できます。
          </p>
        </div>

        <section
          aria-labelledby="new-exchange-heading"
          className="mt-5 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm"
        >
          <h2
            className="text-lg font-bold text-stone-800"
            id="new-exchange-heading"
          >
            新しい交換日記
          </h2>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            フォロー中の人やユーザー検索から相手のプロフィールを開き、交換日記へ招待できます。
          </p>
          <div className="mt-4 grid gap-2 sm:grid-cols-2">
            <Link
              className="flex min-h-11 items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-4 py-2.5 text-center text-sm font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/profile/following"
            >
              フォロー中の人を見る
            </Link>
            <Link
              className="flex min-h-11 items-center justify-center rounded-full border border-stone-300 bg-white px-4 py-2.5 text-center text-sm font-semibold text-stone-700 transition hover:bg-stone-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
              href="/search?category=users"
            >
              ユーザーを検索
            </Link>
          </div>
        </section>

        <nav
          aria-label="交換日記の種類"
          className="mt-5 grid grid-cols-3 gap-1 rounded-2xl bg-stone-100 p-1"
        >
          {(
            [
              ["active", "交換中"],
              ["invitations", "招待"],
              ["archived", "終了"],
            ] as const
          ).map(([view, label]) => (
            <Link
              aria-current={query?.view === view ? "page" : undefined}
              className={`min-w-0 rounded-xl px-2 py-2.5 text-center text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 ${
                query?.view === view
                  ? "bg-white text-orange-800 shadow-sm"
                  : "text-stone-600 hover:bg-white/70 hover:text-stone-800"
              }`}
              href={`/exchange?${buildExchangeTopQuery(view)}`}
              key={view}
            >
              {label}
            </Link>
          ))}
        </nav>

        {!query ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              ページ情報を確認できませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              URLを確認するか、交換日記一覧の最初からもう一度お試しください。
            </p>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-red-300 bg-white px-5 py-2 text-sm font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
              href="/exchange"
            >
              交換日記一覧の最初へ戻る
            </Link>
          </div>
        ) : hasLoadError ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              交換日記を読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : query.view === "invitations" && invitationResult?.data?.length ? (
          <InvitationList items={invitationResult.data} />
        ) : query.view !== "invitations" && diaryResult?.data?.length ? (
          <DiaryList items={diaryResult.data} view={query.view} />
        ) : query.cursor ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              次の交換日記はありません
            </h2>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={`/exchange?${buildExchangeTopQuery(query.view)}`}
            >
              最初の一覧へ戻る
            </Link>
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              {query.view === "active"
                ? "交換中の交換日記はまだありません"
                : query.view === "invitations"
                  ? "現在の招待はありません"
                  : "終了した交換日記はまだありません"}
            </h2>
          </div>
        )}

        {query && nextCursor && (
          <nav aria-label="交換日記一覧のページ移動" className="mt-6">
            <Link
              className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={`/exchange?${buildExchangeTopQuery(query.view, nextCursor)}`}
            >
              次の20件を見る →
            </Link>
          </nav>
        )}

        {query && query.cursor && !nextCursor && !hasLoadError && (
          <p className="mt-6 text-center text-sm text-stone-500">
            現在表示できる交換日記をすべて表示しました。
          </p>
        )}
      </div>
    </section>
  );
}
