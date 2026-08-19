"use client";

import Image from "next/image";
import { useState } from "react";

import type { AdminReportEvidenceItem } from "@/lib/admin-report-detail-data";

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

function EvidenceImage({
  evidence,
  index,
  isOnlyImage,
  reportId,
  total,
}: {
  evidence: AdminReportEvidenceItem;
  index: number;
  isOnlyImage: boolean;
  reportId: string;
  total: number;
}) {
  const [failed, setFailed] = useState(false);
  const label = `通報時点の証拠画像 ${index + 1} / ${total}`;

  return (
    <li className="min-w-0 rounded-2xl border border-stone-200 bg-stone-50 p-3 sm:p-4">
      <h3 className="font-bold text-stone-800">{index + 1}枚目</h3>
      <div
        className={`relative mt-3 min-w-0 overflow-hidden rounded-xl border border-stone-200 bg-white ${
          isOnlyImage ? "aspect-[4/3]" : "aspect-square"
        }`}
      >
        {failed ? (
          <div className="flex size-full items-center justify-center px-3 text-center text-sm leading-6 text-stone-600">
            <span className="sr-only">{label}: </span>
            この画像は現在表示できません。
          </div>
        ) : (
          <Image
            alt={label}
            className="object-contain"
            decoding="async"
            fill
            loading="lazy"
            onError={() => setFailed(true)}
            sizes={
              isOnlyImage
                ? "(max-width: 639px) calc(100vw - 72px), 496px"
                : "(max-width: 639px) calc((100vw - 80px) / 2), 149px"
            }
            src={`/admin/reports/${reportId}/evidence/${evidence.evidenceId}`}
            unoptimized
          />
        )}
      </div>
      <dl className="mt-3 grid min-w-0 grid-cols-2 gap-3">
        <div className="min-w-0">
          <dt className="text-xs font-semibold text-stone-500">形式</dt>
          <dd className="mt-1 text-sm font-semibold text-stone-800">
            {mimeTypeLabels[evidence.mimeType]}
          </dd>
        </div>
        <div className="min-w-0">
          <dt className="text-xs font-semibold text-stone-500">サイズ</dt>
          <dd className="mt-1 break-words text-sm text-stone-700 [overflow-wrap:anywhere]">
            {formatFileSize(evidence.sizeBytes)}
          </dd>
        </div>
      </dl>
    </li>
  );
}

export function AdminReportEvidenceGallery({
  evidence,
  reportId,
}: {
  evidence: readonly AdminReportEvidenceItem[];
  reportId: string;
}) {
  if (evidence.length === 0) {
    return (
      <p className="mt-5 rounded-2xl bg-stone-50 p-5 text-sm leading-6 text-stone-600">
        現在確認できる証拠画像はありません。
      </p>
    );
  }

  const isOnlyImage = evidence.length === 1;
  const columns = isOnlyImage
    ? "grid-cols-1"
    : evidence.length === 2
      ? "grid-cols-2"
      : "grid-cols-2 sm:grid-cols-3";

  return (
    <ol
      aria-label="通報時点の証拠画像"
      className={`mt-5 grid min-w-0 gap-2 sm:gap-3 ${columns}`}
    >
      {evidence.map((item, index) => (
        <EvidenceImage
          evidence={item}
          index={index}
          isOnlyImage={isOnlyImage}
          key={item.evidenceId}
          reportId={reportId}
          total={evidence.length}
        />
      ))}
    </ol>
  );
}
