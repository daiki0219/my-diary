import type { SupabaseClient } from "@supabase/supabase-js";

import {
  EXCHANGE_ENTRY_IMAGE_MAX_COUNT,
} from "@/lib/exchange-entry-image-input";
import { isUuid } from "@/lib/profile-data";

export {
  detectExchangeEntryImageMimeType,
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
  EXCHANGE_ENTRY_IMAGE_BUCKET,
  EXCHANGE_ENTRY_IMAGE_MAX_COUNT,
  EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES,
  isExchangeEntryImageStoragePathFor,
  parseExchangeEntryImageStoragePath,
  type ExchangeEntryImageMimeType,
  type ExchangeEntryImageStoragePath,
} from "@/lib/exchange-entry-image-input";

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

type RawExchangeEntryImageReference = {
  id: string;
  entry_id: string;
  sort_order: number;
};

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
