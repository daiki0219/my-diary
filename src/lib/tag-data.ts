export const TAG_MAX_COUNT = 5;
export const TAG_MAX_CODE_POINTS = 30;
export const TAG_RAW_MAX_COUNT = 20;

const TAG_DELIMITER_PATTERN = /[,，\r\n]/u;
const TAG_CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f-\u009f]/u;

export type PostTag = {
  id: string;
  name: string;
};

export type TagValidationResult =
  | {
      data: string[];
      error: null;
    }
  | {
      data: null;
      error: string;
    };

function trimAsciiSpaces(value: string) {
  return value.replace(/^ +| +$/gu, "");
}

export function normalizeTagName(value: string) {
  let normalized = trimAsciiSpaces(value.normalize("NFKC"));
  normalized = normalized.replace(/^#+/u, "");
  normalized = trimAsciiSpaces(normalized);
  normalized = normalized.replace(/ +/gu, " ");
  return normalized.replace(/[A-Z]/gu, (character) =>
    character.toLowerCase(),
  );
}

export function compareCanonicalTagNames(left: string, right: string) {
  const leftCodePoints = Array.from(left, (character) =>
    character.codePointAt(0) ?? 0,
  );
  const rightCodePoints = Array.from(right, (character) =>
    character.codePointAt(0) ?? 0,
  );
  const sharedLength = Math.min(leftCodePoints.length, rightCodePoints.length);

  for (let index = 0; index < sharedLength; index += 1) {
    const difference = leftCodePoints[index] - rightCodePoints[index];

    if (difference !== 0) {
      return difference;
    }
  }

  return leftCodePoints.length - rightCodePoints.length;
}

export function sortCanonicalTagNames(values: readonly string[]) {
  return [...values].sort(compareCanonicalTagNames);
}

export function splitTagInputValues(values: readonly string[]) {
  return values
    .flatMap((value) => value.split(TAG_DELIMITER_PATTERN))
    .filter((value) => trimAsciiSpaces(value) !== "");
}

export function validateTagInputValues(
  values: readonly string[],
): TagValidationResult {
  const rawTags = splitTagInputValues(values);

  if (rawTags.length > TAG_RAW_MAX_COUNT) {
    return { data: null, error: "タグの入力内容を確認してください。" };
  }

  const canonicalTags: string[] = [];
  const seenTags = new Set<string>();

  for (const rawTag of rawTags) {
    const canonicalTag = normalizeTagName(rawTag);

    if (
      canonicalTag.length === 0 ||
      canonicalTag.includes(",") ||
      canonicalTag.includes("#") ||
      TAG_CONTROL_CHARACTER_PATTERN.test(canonicalTag)
    ) {
      return { data: null, error: "タグの入力内容を確認してください。" };
    }

    if (Array.from(canonicalTag).length > TAG_MAX_CODE_POINTS) {
      return {
        data: null,
        error: "タグは1件30文字以内で入力してください。",
      };
    }

    if (seenTags.has(canonicalTag)) {
      return { data: null, error: "同じタグが重複しています。" };
    }

    seenTags.add(canonicalTag);
    canonicalTags.push(canonicalTag);
  }

  if (canonicalTags.length > TAG_MAX_COUNT) {
    return { data: null, error: "タグは5個まで設定できます。" };
  }

  return { data: sortCanonicalTagNames(canonicalTags), error: null };
}

export function restoreTagInputValues(values: readonly string[]) {
  const rawTags = splitTagInputValues(values);
  const tags: string[] = [];
  const draftValues: string[] = [];
  const seenTags = new Set<string>();

  for (const rawTag of rawTags) {
    const result = validateTagInputValues([rawTag]);
    const canonicalTag = result.data?.[0];

    if (
      !canonicalTag ||
      seenTags.has(canonicalTag) ||
      tags.length >= TAG_MAX_COUNT
    ) {
      draftValues.push(rawTag);
      continue;
    }

    seenTags.add(canonicalTag);
    tags.push(canonicalTag);
  }

  return {
    draft: draftValues.join(", "),
    tags: sortCanonicalTagNames(tags),
  };
}
