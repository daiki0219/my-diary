import { canonicalizeExchangeUuid } from "@/lib/exchange-cursor";
import {
  detectExchangeEntryImageMimeType,
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
  EXCHANGE_ENTRY_IMAGE_BUCKET,
  EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES,
  parseExchangeEntryImageStoragePath,
} from "@/lib/exchange-entry-image-input";
import { getAdminSessionState } from "@/lib/supabase/admin-session";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const allowedMimeTypes = new Set<string>(
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
);
const privateImageHeaders = {
  "Cache-Control": "private, no-store, max-age=0",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Referrer-Policy": "no-referrer",
  Vary: "Cookie",
  "X-Content-Type-Options": "nosniff",
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function notFoundResponse() {
  return new Response(null, {
    headers: privateImageHeaders,
    status: 404,
  });
}

function isVisibleReportRow(value: unknown, expectedReportId: string) {
  return (
    typeof value === "object" &&
    value !== null &&
    hasExactKeys(value, ["id"]) &&
    "id" in value &&
    typeof value.id === "string" &&
    canonicalizeExchangeUuid(value.id) === expectedReportId
  );
}

type ReportEvidenceRow = {
  storagePath: string;
  mimeType: (typeof EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES)[number];
  sizeBytes: number;
};

function parseReportEvidenceRow(
  value: unknown,
  expectedReportId: string,
  expectedEvidenceId: string,
): ReportEvidenceRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, [
      "id",
      "report_id",
      "storage_path",
      "mime_type",
      "size_bytes",
    ]) ||
    !("id" in value) ||
    !("report_id" in value) ||
    !("storage_path" in value) ||
    !("mime_type" in value) ||
    !("size_bytes" in value) ||
    typeof value.id !== "string" ||
    canonicalizeExchangeUuid(value.id) !== expectedEvidenceId ||
    typeof value.report_id !== "string" ||
    canonicalizeExchangeUuid(value.report_id) !== expectedReportId ||
    typeof value.storage_path !== "string" ||
    !parseExchangeEntryImageStoragePath(value.storage_path) ||
    typeof value.mime_type !== "string" ||
    !allowedMimeTypes.has(value.mime_type) ||
    typeof value.size_bytes !== "number" ||
    !Number.isSafeInteger(value.size_bytes) ||
    value.size_bytes < 1 ||
    value.size_bytes > EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES
  ) {
    return null;
  }

  return {
    storagePath: value.storage_path,
    mimeType: value.mime_type as ReportEvidenceRow["mimeType"],
    sizeBytes: value.size_bytes,
  };
}

export async function GET(
  _request: Request,
  context: {
    params: Promise<{ reportId: string; evidenceId: string }>;
  },
) {
  try {
    const { reportId, evidenceId } = await context.params;
    const canonicalReportId = canonicalizeExchangeUuid(reportId);
    const canonicalEvidenceId = canonicalizeExchangeUuid(evidenceId);

    if (!canonicalReportId || !canonicalEvidenceId) {
      return notFoundResponse();
    }

    const supabase = await createClient();
    const adminSession = await getAdminSessionState(supabase);

    if (adminSession.kind !== "active-admin") {
      return notFoundResponse();
    }

    const reportResult = await supabase
      .from("reports")
      .select("id")
      .eq("id", canonicalReportId)
      .limit(2)
      .returns<unknown[]>();

    if (
      reportResult.error ||
      !Array.isArray(reportResult.data) ||
      reportResult.data.length !== 1 ||
      !isVisibleReportRow(reportResult.data[0], canonicalReportId)
    ) {
      return notFoundResponse();
    }

    const evidenceResult = await supabase
      .from("report_snapshot_images")
      .select("id, report_id, storage_path, mime_type, size_bytes")
      .eq("id", canonicalEvidenceId)
      .eq("report_id", canonicalReportId)
      .limit(2)
      .returns<unknown[]>();

    if (
      evidenceResult.error ||
      !Array.isArray(evidenceResult.data) ||
      evidenceResult.data.length !== 1
    ) {
      return notFoundResponse();
    }

    const evidence = parseReportEvidenceRow(
      evidenceResult.data[0],
      canonicalReportId,
      canonicalEvidenceId,
    );

    if (!evidence) {
      return notFoundResponse();
    }

    const downloadResult = await supabase.storage
      .from(EXCHANGE_ENTRY_IMAGE_BUCKET)
      .download(evidence.storagePath, {}, { cache: "no-store" });
    const image = downloadResult.data;
    const blobMimeType = image?.type.toLowerCase();

    if (
      downloadResult.error ||
      !image ||
      !blobMimeType ||
      !allowedMimeTypes.has(blobMimeType) ||
      blobMimeType !== evidence.mimeType ||
      image.size < 1 ||
      image.size > EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES ||
      image.size !== evidence.sizeBytes
    ) {
      return notFoundResponse();
    }

    const detectedMimeType = detectExchangeEntryImageMimeType(
      new Uint8Array(await image.slice(0, 12).arrayBuffer()),
    );

    if (!detectedMimeType || detectedMimeType !== evidence.mimeType) {
      return notFoundResponse();
    }

    return new Response(image, {
      headers: {
        ...privateImageHeaders,
        "Content-Length": String(image.size),
        "Content-Type": detectedMimeType,
      },
      status: 200,
    });
  } catch {
    return notFoundResponse();
  }
}
