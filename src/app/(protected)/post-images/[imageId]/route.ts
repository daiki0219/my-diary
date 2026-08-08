import { isUuid } from "@/lib/profile-data";
import {
  isPostImageStoragePathForPost,
  POST_IMAGE_ALLOWED_MIME_TYPES,
  POST_IMAGE_BUCKET,
  POST_IMAGE_MAX_SIZE_BYTES,
} from "@/lib/post-image-data";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const allowedMimeTypes = new Set<string>(POST_IMAGE_ALLOWED_MIME_TYPES);
const privateImageHeaders = {
  "Cache-Control": "private, no-store, max-age=0",
  "Cross-Origin-Resource-Policy": "same-origin",
  "Referrer-Policy": "no-referrer",
  Vary: "Cookie",
  "X-Content-Type-Options": "nosniff",
};

function notFoundResponse() {
  return new Response(null, {
    headers: privateImageHeaders,
    status: 404,
  });
}

export async function GET(
  _request: Request,
  context: { params: Promise<{ imageId: string }> },
) {
  const { imageId } = await context.params;

  if (!isUuid(imageId)) {
    return notFoundResponse();
  }

  const supabase = await createClient();
  const claimsResult = await supabase.auth.getClaims().catch(() => null);
  const viewerId = claimsResult?.data?.claims?.sub;

  if (
    !claimsResult ||
    claimsResult.error ||
    typeof viewerId !== "string" ||
    !isUuid(viewerId)
  ) {
    return notFoundResponse();
  }

  const metadataResult = await supabase
    .from("post_images")
    .select("post_id, storage_path")
    .eq("id", imageId)
    .limit(1)
    .maybeSingle<{ post_id: string; storage_path: string }>();
  const metadata = metadataResult.data;

  if (
    metadataResult.error ||
    !metadata ||
    typeof metadata.post_id !== "string" ||
    !isUuid(metadata.post_id) ||
    typeof metadata.storage_path !== "string"
  ) {
    return notFoundResponse();
  }

  if (!isPostImageStoragePathForPost(metadata.storage_path, metadata.post_id)) {
    return notFoundResponse();
  }

  const downloadResult = await supabase.storage
    .from(POST_IMAGE_BUCKET)
    .download(metadata.storage_path, {}, { cache: "no-store" });
  const image = downloadResult.data;
  const contentType = image?.type.toLowerCase();

  if (
    downloadResult.error ||
    !image ||
    !contentType ||
    !allowedMimeTypes.has(contentType) ||
    image.size === 0 ||
    image.size > POST_IMAGE_MAX_SIZE_BYTES
  ) {
    return notFoundResponse();
  }

  return new Response(image, {
    headers: {
      ...privateImageHeaders,
      "Content-Length": String(image.size),
      "Content-Type": contentType,
    },
    status: 200,
  });
}
