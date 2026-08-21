import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import {
  getAdminReportPage,
  type AdminReportListItem,
  type AdminReportPageResult,
} from "@/lib/admin-report-data";
import {
  parseAdminReportQuery,
  type AdminReportSearchParams,
} from "@/lib/admin-report-query";
import {
  REPORT_REASON_LABELS,
  REPORT_STATUSES,
  REPORT_STATUS_LABELS,
  REPORT_TARGET_TYPE_LABELS,
  type ReportStatus,
} from "@/lib/report";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type AdminReportsPageProps = {
  searchParams: Promise<AdminReportSearchParams>;
};

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

const statusContent: Record<
  ReportStatus,
  { description: string; emptyMessage: string }
> = {
  pending: {
    description: "未対応の通報を古いものから表示しています。",
    emptyMessage: "現在、未対応の通報はありません。",
  },
  reviewing: {
    description: "確認中の通報を古いものから表示しています。",
    emptyMessage: "現在、確認中の通報はありません。",
  },
  resolved: {
    description: "対応済みの通報を新しいものから表示しています。",
    emptyMessage: "現在、対応済みの通報はありません。",
  },
  dismissed: {
    description: "却下した通報を新しいものから表示しています。",
    emptyMessage: "現在、却下した通報はありません。",
  },
};

function buildAdminReportsUrl(status: ReportStatus, cursor?: string) {
  const searchParams = new URLSearchParams({ status });

  if (cursor) {
    searchParams.set("cursor", cursor);
  }

  return `/admin/reports?${searchParams.toString()}`;
}

function AdminReportList({ items }: { items: AdminReportListItem[] }) {
  return (
    <ul aria-label="通報一覧" className="mt-5 min-w-0 space-y-3">
      {items.map((item) => {
        const targetLabel = REPORT_TARGET_TYPE_LABELS[item.targetType];
        const reasonLabel = REPORT_REASON_LABELS[item.reason];
        const statusLabel = REPORT_STATUS_LABELS[item.status];

        return (
          <li className="min-w-0" key={item.reportId}>
            <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6">
              <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <h2 className="min-w-0 break-words text-lg font-bold leading-7 text-stone-800 [overflow-wrap:anywhere]">
                  {targetLabel}への通報
                </h2>
                <span className="w-fit shrink-0 rounded-full bg-orange-100 px-3 py-1 text-xs font-bold text-orange-800">
                  {statusLabel}
                </span>
              </div>

              <dl className="mt-4 grid min-w-0 gap-4 sm:grid-cols-2">
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">対象</dt>
                  <dd className="mt-1 break-words text-sm font-semibold text-stone-800 [overflow-wrap:anywhere]">
                    {targetLabel}
                  </dd>
                </div>
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">理由</dt>
                  <dd className="mt-1 break-words text-sm font-semibold text-stone-800 [overflow-wrap:anywhere]">
                    {reasonLabel}
                  </dd>
                </div>
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">状態</dt>
                  <dd className="mt-1 text-sm font-semibold text-stone-800">
                    {statusLabel}
                  </dd>
                </div>
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">
                    通報日時
                  </dt>
                  <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                    <time dateTime={item.createdAt}>
                      {dateFormatter.format(new Date(item.createdAt))}
                    </time>
                  </dd>
                </div>
              </dl>

              <Link
                aria-label={`${targetLabel}への${reasonLabel}の通報詳細を確認`}
                className="mt-5 inline-flex min-h-11 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2.5 text-sm font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                href={`/admin/reports/${encodeURIComponent(item.reportId)}`}
              >
                詳細を確認
              </Link>
            </article>
          </li>
        );
      })}
    </ul>
  );
}

function NeutralPageFailure() {
  return (
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
      <div
        className="mx-auto w-full max-w-lg rounded-3xl border border-red-200 bg-red-50 p-6 text-center"
        role="alert"
      >
        <h1 className="text-xl font-bold text-stone-800">
          ページを表示できませんでした
        </h1>
        <p className="mt-3 text-sm leading-6 text-red-700">
          時間をおいて、もう一度お試しください。
        </p>
        <Link
          className="mt-6 inline-flex min-h-11 items-center rounded-full border border-red-300 bg-white px-5 py-3 font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
          href="/home"
        >
          ホームへ戻る
        </Link>
      </div>
    </section>
  );
}

function isUnverifiedFailure(result: AdminReportPageResult) {
  return result.kind === "account-missing" || result.kind === "query-error";
}

export default async function AdminReportsPage({
  searchParams,
}: AdminReportsPageProps) {
  const query = parseAdminReportQuery(await searchParams);
  const result = await getAdminReportPage(query);

  if (result.kind === "unauthenticated") {
    redirect("/login");
  }

  if (result.kind === "denied") {
    notFound();
  }

  if (isUnverifiedFailure(result)) {
    return <NeutralPageFailure />;
  }

  const currentStatus = query?.status ?? null;
  const isInvalidQuery = result.kind === "invalid-query";
  const hasLoadError = result.kind === "error";
  const page = result.kind === "success" ? result : null;
  const currentContent = currentStatus ? statusContent[currentStatus] : null;

  return (
    <section className="flex min-w-0 flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-xl">
        <Link
          className="inline-flex min-h-11 items-center rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ← ホームへ戻る
        </Link>

        <div className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">管理用</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            通報キュー
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            状態ごとに通報を確認できます。この画面では内容の変更は行いません。
          </p>
          <Link
            className="mt-5 inline-flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-white px-5 py-2.5 text-center text-sm font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 sm:w-auto"
            href="/admin/maintenance"
          >
            メンテナンスを確認
          </Link>
        </div>

        <nav
          aria-label="通報の状態"
          className="mt-5 grid min-w-0 grid-cols-2 gap-1 rounded-2xl bg-stone-100 p-1 sm:grid-cols-4"
        >
          {REPORT_STATUSES.map((status) => (
            <Link
              aria-current={currentStatus === status ? "page" : undefined}
              className={`flex min-h-11 min-w-0 items-center justify-center rounded-xl px-2 py-2.5 text-center text-sm font-semibold leading-5 transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 ${
                currentStatus === status
                  ? "bg-white text-orange-800 shadow-sm"
                  : "text-stone-600 hover:bg-white/70 hover:text-stone-800"
              }`}
              href={buildAdminReportsUrl(status)}
              key={status}
            >
              {REPORT_STATUS_LABELS[status]}
            </Link>
          ))}
        </nav>

        {currentContent && !isInvalidQuery && (
          <p className="mt-3 text-sm leading-6 text-stone-600">
            {currentContent.description}
          </p>
        )}

        {isInvalidQuery ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              ページ情報を確認できませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              URLを確認するか、通報一覧の最初からもう一度お試しください。
            </p>
            <Link
              className="mt-5 inline-flex min-h-11 items-center rounded-full border border-red-300 bg-white px-5 py-2.5 text-sm font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
              href="/admin/reports"
            >
              未対応の一覧へ戻る
            </Link>
          </div>
        ) : hasLoadError ? (
          <div
            className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5"
            role="alert"
          >
            <h2 className="font-semibold text-stone-800">
              通報一覧を読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : page && page.items.length > 0 ? (
          <AdminReportList items={page.items} />
        ) : query?.cursor ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              次の通報はありません
            </h2>
            <Link
              className="mt-5 inline-flex min-h-11 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={buildAdminReportsUrl(query.status)}
            >
              最初の一覧へ戻る
            </Link>
          </div>
        ) : currentContent ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              {currentContent.emptyMessage}
            </h2>
          </div>
        ) : null}

        {page?.nextCursor && currentStatus && (
          <nav aria-label="通報一覧のページ移動" className="mt-6">
            <Link
              className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={buildAdminReportsUrl(currentStatus, page.nextCursor)}
            >
              次の20件を見る →
            </Link>
          </nav>
        )}

        {page &&
          query?.cursor &&
          !page.nextCursor &&
          page.items.length > 0 && (
            <p className="mt-6 text-center text-sm text-stone-500">
              現在表示できる通報をすべて表示しました。
            </p>
          )}
      </div>
    </section>
  );
}
