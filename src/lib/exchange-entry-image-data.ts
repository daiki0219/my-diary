import type { SupabaseClient } from "@supabase/supabase-js";

import { isUuid } from "@/lib/profile-data";

export const EXCHANGE_ENTRY_IMAGE_BUCKET = "exchange-entry-images";
export const EXCHANGE_ENTRY_IMAGE_MAX_COUNT = 10;
export const EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES = 6 * 1024 * 1024;
export const EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

const EXCHANGE_ENTRY_IMAGE_METADATA_SHAPE_ERROR = new Error(
  "Exchange entry image metadata shape is invalid.",
);
const EXCHANGE_ENTRY_IMAGE_ENTRY_BATCH_SIZE = 50;
const EXCHANGE_ENTRY_IMAGE_ROW_PAGE_SIZE =
  EXCHANGE_ENTRY_IMAGE_ENTRY_BATCH_SIZE * EXCHANGE_ENTRY_IMAGE_MAX_COUNT;

export type ExchangeEntryImageReference = {
  id: string;
  sortOrder: number;
};

export type ExchangeEntryImageStoragePath = {
  ownerUserId: string;
  diaryId: string;
  entryId: string;
  imageId: string;
};

export type ExchangeEntryImageMimeType =
  (typeof EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES)[number];

type RawExchangeEntryImageReference = {
  id: string;
  entry_id: string;
  sort_order: number;
};

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

function parseRawExchangeEntryImageReference(
  value: unknown,
): RawExchangeEntryImageReference | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }

  const keys = Object.keys(value);

  if (
    keys.length !== 3 ||
    !keys.includes("id") ||
    !keys.includes("entry_id") ||
    !keys.includes("sort_order") ||
    !("id" in value) ||
    !("entry_id" in value) ||
    !("sort_order" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.entry_id !== "string" ||
    !isUuid(value.entry_id) ||
    typeof value.sort_order !== "number" ||
    !Number.isInteger(value.sort_order) ||
    value.sort_order < 0 ||
    value.sort_order >= EXCHANGE_ENTRY_IMAGE_MAX_COUNT
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    entry_id: value.entry_id.toLowerCase(),
    sort_order: value.sort_order,
  };
}

export async function getExchangeEntryImagesByEntryIds(
  supabase: SupabaseClient,
  entryIds: readonly string[],
) {
  const uniqueEntryIds = [
    ...new Set(entryIds.map((entryId) => entryId.toLowerCase())),
  ];

  if (uniqueEntryIds.length === 0) {
    return {
      data: new Map<string, ExchangeEntryImageReference[]>(),
      error: null,
    };
  }

  if (!uniqueEntryIds.every(isUuid)) {
    return {
      data: null,
      error: EXCHANGE_ENTRY_IMAGE_METADATA_SHAPE_ERROR,
    };
  }

  const rawRows: unknown[] = [];

  for (
    let batchStart = 0;
    batchStart < uniqueEntryIds.length;
    batchStart += EXCHANGE_ENTRY_IMAGE_ENTRY_BATCH_SIZE
  ) {
    const entryIdBatch = uniqueEntryIds.slice(
      batchStart,
      batchStart + EXCHANGE_ENTRY_IMAGE_ENTRY_BATCH_SIZE,
    );
    let loadedRowCount = 0;
    let totalRowCount: number | null = null;

    do {
      const result = await supabase
        .from("exchange_entry_images")
        .select("id, entry_id, sort_order", { count: "exact" })
        .in("entry_id", entryIdBatch)
        .order("entry_id", { ascending: true })
        .order("sort_order", { ascending: true })
        .range(
          loadedRowCount,
          loadedRowCount + EXCHANGE_ENTRY_IMAGE_ROW_PAGE_SIZE - 1,
        )
        .returns<unknown[]>();

      if (result.error || !result.data || result.count === null) {
        return {
          data: null,
          error: result.error ?? EXCHANGE_ENTRY_IMAGE_METADATA_SHAPE_ERROR,
        };
      }

      if (
        result.count > entryIdBatch.length * EXCHANGE_ENTRY_IMAGE_MAX_COUNT ||
        (result.data.length === 0 && loadedRowCount < result.count)
      ) {
        return {
          data: null,
          error: EXCHANGE_ENTRY_IMAGE_METADATA_SHAPE_ERROR,
        };
      }

      totalRowCount = result.count;
      loadedRowCount += result.data.length;
      rawRows.push(...result.data);
    } while (loadedRowCount < totalRowCount);
  }

  const allowedEntryIds = new Set(uniqueEntryIds);
  const imageIds = new Set<string>();
  const sortOrdersByEntryId = new Map<string, Set<number>>();
  const imagesByEntryId = new Map<string, ExchangeEntryImageReference[]>();

  for (const value of rawRows) {
    const row = parseRawExchangeEntryImageReference(value);

    if (
      !row ||
      !allowedEntryIds.has(row.entry_id) ||
      imageIds.has(row.id)
    ) {
      return {
        data: null,
        error: EXCHANGE_ENTRY_IMAGE_METADATA_SHAPE_ERROR,
      };
    }

    const sortOrders =
      sortOrdersByEntryId.get(row.entry_id) ?? new Set<number>();
    const images = imagesByEntryId.get(row.entry_id) ?? [];

    if (
      sortOrders.has(row.sort_order) ||
      images.length >= EXCHANGE_ENTRY_IMAGE_MAX_COUNT
    ) {
      return {
        data: null,
        error: EXCHANGE_ENTRY_IMAGE_METADATA_SHAPE_ERROR,
      };
    }

    imageIds.add(row.id);
    sortOrders.add(row.sort_order);
    sortOrdersByEntryId.set(row.entry_id, sortOrders);
    images.push({ id: row.id, sortOrder: row.sort_order });
    imagesByEntryId.set(row.entry_id, images);
  }

  for (const images of imagesByEntryId.values()) {
    images.sort((left, right) => left.sortOrder - right.sortOrder);
  }

  return { data: imagesByEntryId, error: null };
}
