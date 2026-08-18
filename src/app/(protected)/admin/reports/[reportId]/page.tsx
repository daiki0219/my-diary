import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { AdminReportStatusActions } from "@/components/admin/admin-report-status-actions";
import {
  getAdminReportDetail,
  type AdminReportDetailResult,
} from "@/lib/admin-report-detail-data";
import { getMoodLabel } from "@/lib/post-data";
import {
  REPORT_REASON_LABELS,
  REPORT_STATUS_LABELS,
  REPORT_TARGET_TYPE_LABELS,
} from "@/lib/report";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type AdminReportDetailPageProps = {
  params: Promise<{ reportId: string }>;
};

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

const numberFormatter = new Intl.NumberFormat("ja-JP", {
  maximumFractionDigits: 1,
});

const mimeTypeLabels = {
  "image/jpeg": "JPEG",
  "image/png": "PNG",
  "image/webp": "WebP",
} as const;

function formatFileSize(sizeBytes: number) {
  if (sizeBytes >= 1024 * 1024) {
    return `${numberFormatter.format(sizeBytes / (1024 * 1024))} MB`;
  }

  if (sizeBytes >= 1024) {
    return `${numberFormatter.format(sizeBytes / 1024)} KB`;
  }

  return `${numberFormatter.format(sizeBytes)} byte`;
}

function isUnverifiedFailure(result: AdminReportDetailResult) {
  return result.kind === "account-missing" || result.kind === "query-error";
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

function ReportLoadFailure() {
  return (
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
      <div
        className="mx-auto w-full max-w-lg rounded-3xl border border-red-200 bg-red-50 p-6 text-center"
        role="alert"
      >
        <h1 className="text-xl font-bold text-stone-800">
          通報内容を読み込めませんでした
        </h1>
        <p className="mt-3 text-sm leading-6 text-red-700">
          時間をおいて、もう一度お試しください。
        </p>
        <Link
          className="mt-6 inline-flex min-h-11 items-center rounded-full border border-red-300 bg-white px-5 py-3 font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
          href="/admin/reports"
        >
          通報一覧へ戻る
        </Link>
      </div>
    </section>
  );
}

export default async function AdminReportDetailPage({
  params,
}: AdminReportDetailPageProps) {
  const { reportId } = await params;
  const result = await getAdminReportDetail(reportId);

  if (result.kind === "unauthenticated") {
    redirect("/login");
  }

  if (result.kind === "denied" || result.kind === "not-found") {
    notFound();
  }

  if (isUnverifiedFailure(result)) {
    return <NeutralPageFailure />;
  }

  if (result.kind === "error") {
    return <ReportLoadFailure />;
  }

  const { report, snapshot, evidence } = result.detail;
  const targetLabel = REPORT_TARGET_TYPE_LABELS[report.targetType];
  const reasonLabel = REPORT_REASON_LABELS[report.reason];
  const statusLabel = REPORT_STATUS_LABELS[report.status];

  return (
    <section className="flex min-w-0 flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-xl">
        <Link
          className="inline-flex min-h-11 items-center rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/admin/reports"
        >
          ← 通報一覧へ戻る
        </Link>

        <header className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">管理用</p>
          <h1 className="mt-2 break-words text-3xl font-bold tracking-tight text-stone-800 [overflow-wrap:anywhere]">
            通報の詳細
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            通報時点の記録と現在の対応状況を表示しています。
          </p>
        </header>

        <section
          aria-labelledby="report-summary-heading"
          className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
        >
          <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <h2
              className="break-words text-xl font-bold text-stone-800 [overflow-wrap:anywhere]"
              id="report-summary-heading"
            >
              通報の概要
            </h2>
            <span className="w-fit shrink-0 rounded-full bg-orange-100 px-3 py-1 text-xs font-bold text-orange-800">
              {statusLabel}
            </span>
          </div>

          <dl className="mt-5 grid min-w-0 gap-4 sm:grid-cols-2">
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
                <time dateTime={report.createdAt}>
                  {dateFormatter.format(new Date(report.createdAt))}
                </time>
              </dd>
            </div>
            {report.resolvedAt && (
              <div className="min-w-0">
                <dt className="text-xs font-semibold text-stone-500">
                  対応日時
                </dt>
                <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                  <time dateTime={report.resolvedAt}>
                    {dateFormatter.format(new Date(report.resolvedAt))}
                  </time>
                </dd>
              </div>
            )}
          </dl>
        </section>

        <AdminReportStatusActions
          currentStatus={report.status}
          reportId={reportId.toLowerCase()}
        />

        <section
          aria-labelledby="report-details-heading"
          className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
        >
          <h2
            className="text-xl font-bold text-stone-800"
            id="report-details-heading"
          >
            通報内容
          </h2>
          {report.details ? (
            <p className="mt-4 min-w-0 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
              {report.details}
            </p>
          ) : (
            <p className="mt-4 text-sm leading-6 text-stone-600">
              追加の説明はありません。
            </p>
          )}
        </section>

        <section
          aria-labelledby="report-snapshot-heading"
          className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-stone-50 p-5 sm:p-6"
        >
          <h2
            className="text-xl font-bold text-stone-800"
            id="report-snapshot-heading"
          >
            関連日記の記録
          </h2>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            通報時点に固定された関連日記の記録です。
          </p>

          {snapshot ? (
            <article className="mt-5 min-w-0 rounded-3xl bg-white p-5 shadow-sm sm:p-6">
              <h3 className="break-words text-xl font-bold leading-8 text-stone-800 [overflow-wrap:anywhere]">
                {snapshot.title ?? "タイトルなし"}
              </h3>

              <dl className="mt-5 grid min-w-0 gap-4 sm:grid-cols-2">
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">
                    記録日時
                  </dt>
                  <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                    <time dateTime={snapshot.capturedAt}>
                      {dateFormatter.format(new Date(snapshot.capturedAt))}
                    </time>
                  </dd>
                </div>
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">
                    元の記録の作成日時
                  </dt>
                  <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                    <time dateTime={snapshot.entryCreatedAt}>
                      {dateFormatter.format(new Date(snapshot.entryCreatedAt))}
                    </time>
                  </dd>
                </div>
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">
                    元の記録の更新日時
                  </dt>
                  <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                    <time dateTime={snapshot.entryUpdatedAt}>
                      {dateFormatter.format(new Date(snapshot.entryUpdatedAt))}
                    </time>
                  </dd>
                </div>
                <div className="min-w-0">
                  <dt className="text-xs font-semibold text-stone-500">
                    気分
                  </dt>
                  <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                    {getMoodLabel(snapshot.mood)}
                  </dd>
                </div>
                <div className="min-w-0 sm:col-span-2">
                  <dt className="text-xs font-semibold text-stone-500">
                    場所
                  </dt>
                  <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                    {snapshot.locationName ?? "場所は未設定"}
                  </dd>
                </div>
              </dl>

              <div className="mt-6 min-w-0">
                <h4 className="font-bold text-stone-800">本文</h4>
                <p className="mt-3 min-w-0 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
                  {snapshot.body}
                </p>
              </div>

              <div className="mt-6 min-w-0">
                <h4 className="font-bold text-stone-800">タグ</h4>
                {snapshot.tagNames.length > 0 ? (
                  <ul className="mt-3 flex min-w-0 max-w-full flex-wrap gap-2">
                    {snapshot.tagNames.map((tagName) => (
                      <li className="min-w-0 max-w-full" key={tagName}>
                        <span className="inline-flex max-w-full break-words rounded-full border border-orange-200 bg-orange-50 px-3 py-1 text-xs font-semibold text-orange-900 [overflow-wrap:anywhere]">
                          #{tagName}
                        </span>
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p className="mt-3 text-sm text-stone-600">
                    タグはありません。
                  </p>
                )}
              </div>
            </article>
          ) : (
            <p className="mt-5 rounded-2xl bg-white p-5 text-sm leading-6 text-stone-600 shadow-sm">
              現在確認できる関連日記の記録はありません。
            </p>
          )}
        </section>

        <section
          aria-labelledby="report-evidence-heading"
          className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
        >
          <h2
            className="text-xl font-bold text-stone-800"
            id="report-evidence-heading"
          >
            画像証拠
          </h2>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            現在確認できる画像証拠は{evidence.length}件です。画像自体はこの画面では表示しません。
          </p>

          {evidence.length > 0 ? (
            <ol className="mt-5 grid min-w-0 gap-3 sm:grid-cols-2">
              {evidence.map((item, index) => (
                <li
                  className="min-w-0 rounded-2xl border border-stone-200 bg-stone-50 p-4"
                  key={item.sortOrder}
                >
                  <h3 className="font-bold text-stone-800">
                    {index + 1}枚目
                  </h3>
                  <dl className="mt-3 grid min-w-0 gap-3">
                    <div className="min-w-0">
                      <dt className="text-xs font-semibold text-stone-500">
                        形式
                      </dt>
                      <dd className="mt-1 text-sm font-semibold text-stone-800">
                        {mimeTypeLabels[item.mimeType]}
                      </dd>
                    </div>
                    <div className="min-w-0">
                      <dt className="text-xs font-semibold text-stone-500">
                        サイズ
                      </dt>
                      <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
                        {formatFileSize(item.sizeBytes)}
                      </dd>
                    </div>
                  </dl>
                </li>
              ))}
            </ol>
          ) : (
            <p className="mt-5 rounded-2xl bg-stone-50 p-5 text-sm leading-6 text-stone-600">
              現在確認できる画像証拠の記録はありません。
            </p>
          )}
        </section>
      </div>
    </section>
  );
}
