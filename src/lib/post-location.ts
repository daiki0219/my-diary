export const POST_LOCATION_NAME_MAX_LENGTH = 100;

export const POST_LOCATION_NAME_ERROR =
  `場所は${POST_LOCATION_NAME_MAX_LENGTH}文字以内で入力してください。`;

export function normalizePostLocationName(value: string) {
  const normalized = value.trim();
  return normalized === "" ? null : normalized;
}

export function getPostLocationNameCharacterCount(value: string) {
  return Array.from(value).length;
}

export function getPostLocationNameError(value: string) {
  const normalized = normalizePostLocationName(value);

  if (
    normalized !== null &&
    getPostLocationNameCharacterCount(normalized) >
      POST_LOCATION_NAME_MAX_LENGTH
  ) {
    return POST_LOCATION_NAME_ERROR;
  }

  return null;
}
