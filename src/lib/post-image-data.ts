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
    segments.length === 3 &&
    segments[0] === userId &&
    segments[1] === postId &&
    isUuid(segments[2])
  );
}
