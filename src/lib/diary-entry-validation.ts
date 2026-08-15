import { isPostMood, type PostMood } from "@/lib/post-data";
import {
  getPostLocationNameError,
  normalizePostLocationName,
} from "@/lib/post-location";
import { validateTagInputValues } from "@/lib/tag-data";

export const DIARY_ENTRY_TITLE_MAX_CODE_POINTS = 120;
export const DIARY_ENTRY_BODY_MAX_CODE_POINTS = 10_000;

export type DiaryEntryField =
  | "title"
  | "body"
  | "mood"
  | "location"
  | "tags";

export type DiaryEntryFieldErrors = Partial<
  Record<DiaryEntryField, string>
>;

export type DiaryEntryInput = {
  title: string | null;
  body: string;
  mood: PostMood | null;
  locationName: string | null;
  tags: string[];
};

export type DiaryEntryValidationResult = {
  data: DiaryEntryInput | null;
  fieldErrors: DiaryEntryFieldErrors;
  submittedTagValues: string[];
};

export function getUnicodeCodePointCount(value: string) {
  return Array.from(value).length;
}

export function normalizeDiaryEntryBody(value: string) {
  return value.replace(/\r\n?/gu, "\n").trim();
}

export function validateDiaryEntryFormData(
  formData: FormData,
): DiaryEntryValidationResult {
  const titleValue = formData.get("title");
  const bodyValue = formData.get("body");
  const moodValue = formData.get("mood");
  const locationValue = formData.get("locationName");
  const tagEntries = formData.getAll("tags");
  const submittedTagValues = tagEntries.filter(
    (entry): entry is string => typeof entry === "string",
  );
  const fieldErrors: DiaryEntryFieldErrors = {};

  if (typeof titleValue !== "string") {
    fieldErrors.title = "タイトルを正しく入力してください。";
  }

  if (typeof bodyValue !== "string") {
    fieldErrors.body = "本文を入力してください。";
  }

  if (typeof moodValue !== "string") {
    fieldErrors.mood = "気分を正しく選択してください。";
  }

  if (typeof locationValue !== "string") {
    fieldErrors.location = "場所を正しく入力してください。";
  }

  if (submittedTagValues.length !== tagEntries.length) {
    fieldErrors.tags = "タグの入力内容を確認してください。";
  }

  const normalizedTitle =
    typeof titleValue === "string" ? titleValue.trim() : "";
  const title = normalizedTitle === "" ? null : normalizedTitle;
  const body =
    typeof bodyValue === "string" ? normalizeDiaryEntryBody(bodyValue) : "";
  const normalizedMood =
    typeof moodValue === "string" ? moodValue.trim() : "";
  const mood = normalizedMood === "" ? null : normalizedMood;
  const locationName =
    typeof locationValue === "string"
      ? normalizePostLocationName(locationValue)
      : null;

  if (
    title !== null &&
    getUnicodeCodePointCount(title) > DIARY_ENTRY_TITLE_MAX_CODE_POINTS
  ) {
    fieldErrors.title = "タイトルは120文字以下で入力してください。";
  }

  const bodyLength = getUnicodeCodePointCount(body);

  if (bodyLength < 1) {
    fieldErrors.body = "本文を入力してください。";
  } else if (bodyLength > DIARY_ENTRY_BODY_MAX_CODE_POINTS) {
    fieldErrors.body = "本文は10,000文字以下で入力してください。";
  }

  if (mood !== null && !isPostMood(mood)) {
    fieldErrors.mood = "選択された気分は使用できません。";
  }

  if (typeof locationValue === "string") {
    const locationError = getPostLocationNameError(locationValue);

    if (locationError) {
      fieldErrors.location = locationError;
    }
  }

  const tagResult = validateTagInputValues(submittedTagValues);

  if (tagResult.error) {
    fieldErrors.tags = tagResult.error;
  }

  if (Object.keys(fieldErrors).length > 0 || !tagResult.data) {
    return { data: null, fieldErrors, submittedTagValues };
  }

  return {
    data: {
      title,
      body,
      mood: mood as PostMood | null,
      locationName,
      tags: tagResult.data,
    },
    fieldErrors: {},
    submittedTagValues,
  };
}
