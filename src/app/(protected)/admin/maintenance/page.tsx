import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { AdminMaintenanceConfirmedImageCleanup } from "@/components/admin/admin-maintenance-confirmed-image-cleanup";
import { AdminMaintenanceEvidencePurge } from "@/components/admin/admin-maintenance-evidence-purge";
import { AdminMaintenanceOrphanImageCleanup } from "@/components/admin/admin-maintenance-orphan-image-cleanup";
import {
  ADMIN_EVIDENCE_PURGE_BATCH_SIZE,
  ADMIN_EXCHANGE_IMAGE_CLEANUP_BATCH_SIZE,
  getAdminMaintenanceSummary,
} from "@/lib/admin-maintenance-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

function formatDueLabel(value: string | null) {
  return value
    ? `${dateFormatter.format(new Date(value))}（日本時間）`
    : null;
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

export default async function AdminMaintenancePage() {
  const result = await getAdminMaintenanceSummary();

  if (result.kind === "unauthenticated") {
    redirect("/login");
  }

  if (result.kind === "denied") {
    notFound();
  }

  if (result.kind === "account-missing" || result.kind === "query-error") {
    return <NeutralPageFailure />;
  }

  const summary = result.kind === "success" ? result.summary : null;
  const oldestConfirmedDueAt =
    summary?.oldestConfirmedCleanupDueAt ?? null;
  const oldestOrphanDueAt = summary?.oldestUnconfirmedOrphanDueAt ?? null;
  const oldestEvidenceDueAt = summary?.oldestReportEvidenceDueAt ?? null;

  return (
    <section className="flex min-w-0 flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-xl">
        <Link
          className="inline-flex min-h-11 items-center rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/admin/reports"
        >
          ← 通報キューへ戻る
        </Link>

        <div className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">管理用</p>
          <h1 className="mt-2 break-words text-3xl font-bold tracking-tight text-stone-800 [overflow-wrap:anywhere]">
            メンテナンス
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            保持期限を過ぎた交換日記画像と通報証拠を、現在の権限と状態を再確認して手動で処理します。
          </p>
        </div>

        <AdminMaintenanceConfirmedImageCleanup
          batchSize={ADMIN_EXCHANGE_IMAGE_CLEANUP_BATCH_SIZE}
          dueCount={summary?.dueConfirmedCleanupCandidateCount ?? null}
          oldestDueAt={oldestConfirmedDueAt}
          oldestDueLabel={formatDueLabel(oldestConfirmedDueAt)}
        />
        <AdminMaintenanceOrphanImageCleanup
          batchSize={ADMIN_EXCHANGE_IMAGE_CLEANUP_BATCH_SIZE}
          dueCount={summary?.dueUnconfirmedOrphanCount ?? null}
          oldestDueAt={oldestOrphanDueAt}
          oldestDueLabel={formatDueLabel(oldestOrphanDueAt)}
        />
        <AdminMaintenanceEvidencePurge
          batchSize={ADMIN_EVIDENCE_PURGE_BATCH_SIZE}
          dueCount={summary?.dueReportEvidenceCount ?? null}
          oldestDueAt={oldestEvidenceDueAt}
          oldestDueLabel={formatDueLabel(oldestEvidenceDueAt)}
        />
      </div>
    </section>
  );
}
