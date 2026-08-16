import { getUnicodeCodePointCount } from "@/lib/diary-entry-validation";

export const EXCHANGE_ENTRY_REPORT_DETAILS_MAX_CODE_POINTS = 2_000;

export const EXCHANGE_ENTRY_REPORT_REASONS = [
  "harassment",
  "spam",
  "personal_information",
  "sexual_or_inappropriate",
  "threat_or_danger",
  "other",
] as const;

export type ExchangeEntryReportReason =
  (typeof EXCHANGE_ENTRY_REPORT_REASONS)[number];

export const EXCHANGE_ENTRY_REPORT_REASON_OPTIONS: ReadonlyArray<{
  value: ExchangeEntryReportReason;
  label: string;
}> = [
  { value: "harassment", label: "嫌がらせ・誹謗中傷" },
  { value: "spam", label: "スパム・大量投稿" },
  { value: "personal_information", label: "個人情報" },
  { value: "sexual_or_inappropriate", label: "性的・不適切な内容" },
  { value: "threat_or_danger", label: "脅迫・危険な内容" },
  { value: "other", label: "その他" },
];

export type ExchangeEntryReportFieldErrors = {
  reason?: string;
  details?: string;
};

export type ExchangeEntryReportInput = {
  reason: ExchangeEntryReportReason;
  details: string | null;
};

export type ExchangeEntryReportValidationResult = {
  data: ExchangeEntryReportInput | null;
  fieldErrors: ExchangeEntryReportFieldErrors;
  submittedReason: string;
  submittedDetails: string;
};

export function isExchangeEntryReportReason(
  value: string,
): value is ExchangeEntryReportReason {
  return EXCHANGE_ENTRY_REPORT_REASONS.some((reason) => reason === value);
}

export function validateExchangeEntryReportValues(
  reasonValue: unknown,
  detailsValue: unknown,
): ExchangeEntryReportValidationResult {
  const fieldErrors: ExchangeEntryReportFieldErrors = {};
  const submittedReason =
    typeof reasonValue === "string" ? reasonValue : "";
  const submittedDetails =
    typeof detailsValue === "string" ? detailsValue : "";

  if (typeof reasonValue !== "string" || submittedReason === "") {
    fieldErrors.reason = "通報理由を選択してください。";
  } else if (!isExchangeEntryReportReason(submittedReason)) {
    fieldErrors.reason = "選択された通報理由は使用できません。";
  }

  if (typeof detailsValue !== "string") {
    fieldErrors.details = "詳細を正しく入力してください。";
  }

  const normalizedDetails = submittedDetails.trim();
  const details = normalizedDetails === "" ? null : normalizedDetails;

  if (
    details !== null &&
    getUnicodeCodePointCount(details) >
      EXCHANGE_ENTRY_REPORT_DETAILS_MAX_CODE_POINTS
  ) {
    fieldErrors.details = "詳細は2,000文字以下で入力してください。";
  } else if (submittedReason === "other" && details === null) {
    fieldErrors.details = "「その他」を選んだ場合は詳細を入力してください。";
  }

  if (
    Object.keys(fieldErrors).length > 0 ||
    !isExchangeEntryReportReason(submittedReason)
  ) {
    return {
      data: null,
      fieldErrors,
      submittedReason,
      submittedDetails,
    };
  }

  return {
    data: {
      reason: submittedReason,
      details,
    },
    fieldErrors: {},
    submittedReason,
    submittedDetails,
  };
}

export function validateExchangeEntryReportFormData(formData: FormData) {
  const reasonEntries = formData.getAll("reason");
  const detailsEntries = formData.getAll("details");

  return validateExchangeEntryReportValues(
    reasonEntries.length === 1 ? reasonEntries[0] : null,
    detailsEntries.length === 1 ? detailsEntries[0] : null,
  );
}
