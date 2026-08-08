import type { SupabaseClient } from "@supabase/supabase-js";

import { isUuid } from "@/lib/profile-data";

export const POST_IMAGE_BUCKET = "post-images";
export const POST_IMAGE_MAX_COUNT = 10;
export const POST_IMAGE_MAX_SIZE_BYTES = 6 * 1024 * 1024;
export const POST_IMAGE_ALLOWED_MIME_TYPES = [
  "image/jpeg",
  "image/png",
  "image/webp",
] as const;

const allowedMimeTypes = new Set<string>(POST_IMAGE_ALLOWED_MIME_TYPES);
const POST_IMAGE_METADATA_SHAPE_ERROR = new Error(
  "Post image metadata shape is invalid.",
);
const POST_IMAGE_POST_BATCH_SIZE = 50;
const POST_IMAGE_ROW_PAGE_SIZE =
  POST_IMAGE_POST_BATCH_SIZE * POST_IMAGE_MAX_COUNT;

export type PostImageReference = {
  id: string;
  sortOrder: number;
};

type RawPostImageReference = {
  id: string;
  post_id: string;
  sort_order: number;
};

export type PostImageFileValidation =
  | { error: null }
  | { error: string };

export function validatePostImageFiles(
  files: readonly File[],
): PostImageFileValidation {
  if (files.length > POST_IMAGE_MAX_COUNT) {
    return { error: `画像は最大${POST_IMAGE_MAX_COUNT}枚まで選択できます。` };
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

    if (file.size > POST_IMAGE_MAX_SIZE_BYTES) {
      return { error: "画像1枚の容量は6MB以下にしてください。" };
    }
  }

  return { error: null };
}

export function createPostImageStoragePath(
  userId: string,
  postId: string,
  imageId: string,
) {
  if (!isUuid(userId) || !isUuid(postId) || !isUuid(imageId)) {
    throw new Error("A post image path requires UUID identifiers.");
  }

  return `${userId}/${postId}/${imageId}`;
}

export function isPostImageStoragePathFor(
  path: string,
  userId: string,
  postId: string,
) {
  const segments = path.split("/");

  return (
    isUuid(userId) &&
    segments[0] === userId &&
    isPostImageStoragePathForPost(path, postId)
  );
}

export function isPostImageStoragePathForPost(
  path: string,
  postId: string,
) {
  const segments = path.split("/");

  return (
    isUuid(postId) &&
    segments.length === 3 &&
    isUuid(segments[0]) &&
    segments[1] === postId &&
    isUuid(segments[2])
  );
}

function isRawPostImageReference(
  value: unknown,
): value is RawPostImageReference {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const keys = Object.keys(value);

  return (
    keys.length === 3 &&
    keys.includes("id") &&
    keys.includes("post_id") &&
    keys.includes("sort_order") &&
    "id" in value &&
    "post_id" in value &&
    "sort_order" in value &&
    typeof value.id === "string" &&
    isUuid(value.id) &&
    typeof value.post_id === "string" &&
    isUuid(value.post_id) &&
    typeof value.sort_order === "number" &&
    Number.isInteger(value.sort_order) &&
    value.sort_order >= 0 &&
    value.sort_order < POST_IMAGE_MAX_COUNT
  );
}

export async function getPostImagesByPostIds(
  supabase: SupabaseClient,
  postIds: readonly string[],
) {
  const uniquePostIds = [...new Set(postIds)];

  if (uniquePostIds.length === 0) {
    return {
      data: new Map<string, PostImageReference[]>(),
      error: null,
    };
  }

  if (!uniquePostIds.every(isUuid)) {
    return { data: null, error: POST_IMAGE_METADATA_SHAPE_ERROR };
  }

  const rawRows: unknown[] = [];

  for (
    let batchStart = 0;
    batchStart < uniquePostIds.length;
    batchStart += POST_IMAGE_POST_BATCH_SIZE
  ) {
    const postIdBatch = uniquePostIds.slice(
      batchStart,
      batchStart + POST_IMAGE_POST_BATCH_SIZE,
    );
    let loadedRowCount = 0;
    let totalRowCount: number | null = null;

    do {
      const result = await supabase
        .from("post_images")
        .select("id, post_id, sort_order", { count: "exact" })
        .in("post_id", postIdBatch)
        .order("post_id", { ascending: true })
        .order("sort_order", { ascending: true })
        .range(
          loadedRowCount,
          loadedRowCount + POST_IMAGE_ROW_PAGE_SIZE - 1,
        )
        .returns<unknown[]>();

      if (result.error || !result.data || result.count === null) {
        return {
          data: null,
          error: result.error ?? POST_IMAGE_METADATA_SHAPE_ERROR,
        };
      }

      if (
        result.count > postIdBatch.length * POST_IMAGE_MAX_COUNT ||
        (result.data.length === 0 && loadedRowCount < result.count)
      ) {
        return { data: null, error: POST_IMAGE_METADATA_SHAPE_ERROR };
      }

      totalRowCount = result.count;
      loadedRowCount += result.data.length;
      rawRows.push(...result.data);
    } while (loadedRowCount < totalRowCount);
  }

  const allowedPostIds = new Set(uniquePostIds);
  const imageIds = new Set<string>();
  const sortOrdersByPostId = new Map<string, Set<number>>();
  const imagesByPostId = new Map<string, PostImageReference[]>();

  for (const row of rawRows) {
    if (
      !isRawPostImageReference(row) ||
      !allowedPostIds.has(row.post_id) ||
      imageIds.has(row.id)
    ) {
      return { data: null, error: POST_IMAGE_METADATA_SHAPE_ERROR };
    }

    const sortOrders = sortOrdersByPostId.get(row.post_id) ?? new Set<number>();
    const images = imagesByPostId.get(row.post_id) ?? [];

    if (
      sortOrders.has(row.sort_order) ||
      images.length >= POST_IMAGE_MAX_COUNT
    ) {
      return { data: null, error: POST_IMAGE_METADATA_SHAPE_ERROR };
    }

    imageIds.add(row.id);
    sortOrders.add(row.sort_order);
    sortOrdersByPostId.set(row.post_id, sortOrders);
    images.push({ id: row.id, sortOrder: row.sort_order });
    imagesByPostId.set(row.post_id, images);
  }

  for (const images of imagesByPostId.values()) {
    images.sort((left, right) => left.sortOrder - right.sortOrder);
  }

  return { data: imagesByPostId, error: null };
}
