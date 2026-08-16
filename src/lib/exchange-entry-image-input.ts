import { isUuid } from "@/lib/profile-data";

export const EXCHANGE_ENTRY_IMAGE_BUCKET = "exchange-entry-images";
export const EXCHANGE_ENTRY_IMAGE_MAX_COUNT = 10;
export const EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES = 6 * 1024 * 1024;
export const EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

const allowedMimeTypes = new Set<string>(
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
);

export type ExchangeEntryImageStoragePath = {
  ownerUserId: string;
  diaryId: string;
  entryId: string;
  imageId: string;
};

export type ExchangeEntryImageMimeType =
  (typeof EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES)[number];

export type ExchangeEntryImageFileValidation =
  | { error: null }
  | { error: string };

export function parseExchangeEntryImageStoragePath(
  path: string,
): ExchangeEntryImageStoragePath | null {
  const segments = path.split("/");

  if (
    segments.length !== 4 ||
    !segments.every(
      (segment) => isUuid(segment) && segment === segment.toLowerCase(),
    )
  ) {
    return null;
  }

  return {
    ownerUserId: segments[0],
    diaryId: segments[1],
    entryId: segments[2],
    imageId: segments[3],
  };
}

export function createExchangeEntryImageStoragePath(
  identifiers: ExchangeEntryImageStoragePath,
) {
  if (!Object.values(identifiers).every(isUuid)) {
    throw new Error("An exchange entry image path requires UUID identifiers.");
  }

  return [
    identifiers.ownerUserId,
    identifiers.diaryId,
    identifiers.entryId,
    identifiers.imageId,
  ]
    .map((identifier) => identifier.toLowerCase())
    .join("/");
}

export function isExchangeEntryImageStoragePathFor(
  path: string,
  expected: ExchangeEntryImageStoragePath,
) {
  const parsed = parseExchangeEntryImageStoragePath(path);

  if (!parsed || !Object.values(expected).every(isUuid)) {
    return false;
  }

  return (
    parsed.ownerUserId === expected.ownerUserId.toLowerCase() &&
    parsed.diaryId === expected.diaryId.toLowerCase() &&
    parsed.entryId === expected.entryId.toLowerCase() &&
    parsed.imageId === expected.imageId.toLowerCase()
  );
}

export function detectExchangeEntryImageMimeType(
  bytes: Uint8Array,
): ExchangeEntryImageMimeType | null {
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "image/jpeg";
  }

  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) {
    return "image/png";
  }

  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 &&
    bytes[1] === 0x49 &&
    bytes[2] === 0x46 &&
    bytes[3] === 0x46 &&
    bytes[8] === 0x57 &&
    bytes[9] === 0x45 &&
    bytes[10] === 0x42 &&
    bytes[11] === 0x50
  ) {
    return "image/webp";
  }

  return null;
}

export async function validateExchangeEntryImageFiles(
  files: readonly File[],
): Promise<ExchangeEntryImageFileValidation> {
  if (files.length > EXCHANGE_ENTRY_IMAGE_MAX_COUNT) {
    return {
      error: `画像は最大${EXCHANGE_ENTRY_IMAGE_MAX_COUNT}枚まで選択できます。`,
    };
  }

  for (const file of files) {
    if (!allowedMimeTypes.has(file.type)) {
      return {
        error: "JPEG、PNG、WebP形式の画像を選択してください。",
      };
    }

    if (file.size === 0) {
      return { error: "空の画像ファイルは選択できません。" };
    }

    if (file.size > EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES) {
      return { error: "画像1枚の容量は6MB以下にしてください。" };
    }

    let detectedMimeType: ExchangeEntryImageMimeType | null;

    try {
      detectedMimeType = detectExchangeEntryImageMimeType(
        new Uint8Array(await file.slice(0, 12).arrayBuffer()),
      );
    } catch {
      return { error: "画像ファイルを読み取れませんでした。" };
    }

    if (detectedMimeType !== file.type) {
      return {
        error: "画像の形式とファイル内容が一致していません。",
      };
    }
  }

  return { error: null };
}
