import { canonicalizeExchangeUuid } from "@/lib/exchange-cursor";
import {
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
  EXCHANGE_ENTRY_IMAGE_BUCKET,
  EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES,
  detectExchangeEntryImageMimeType,
  isExchangeEntryImageStoragePathFor,
} from "@/lib/exchange-entry-image-data";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const allowedMimeTypes = new Set<string>(
  EXCHANGE_ENTRY_IMAGE_ALLOWED_MIME_TYPES,
);
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
  try {
    const { imageId } = await context.params;
    const canonicalImageId = canonicalizeExchangeUuid(imageId);

    if (!canonicalImageId) {
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
      .from("exchange_entry_images")
      .select("id, entry_id, storage_path")
      .eq("id", canonicalImageId)
      .limit(2)
      .returns<unknown[]>();

    if (
      metadataResult.error ||
      !metadataResult.data ||
      metadataResult.data.length !== 1
    ) {
      return notFoundResponse();
    }

    const metadata = metadataResult.data[0];

    if (
      typeof metadata !== "object" ||
      metadata === null ||
      !("id" in metadata) ||
      !("entry_id" in metadata) ||
      !("storage_path" in metadata) ||
      typeof metadata.id !== "string" ||
      !isUuid(metadata.id) ||
      metadata.id.toLowerCase() !== canonicalImageId ||
      typeof metadata.entry_id !== "string" ||
      !isUuid(metadata.entry_id) ||
      typeof metadata.storage_path !== "string"
    ) {
      return notFoundResponse();
    }

    const canonicalEntryId = metadata.entry_id.toLowerCase();
    const entryResult = await supabase
      .from("exchange_entries")
      .select("id, diary_id, author_participant_id, deleted_at")
      .eq("id", canonicalEntryId)
      .is("deleted_at", null)
      .limit(2)
      .returns<unknown[]>();

    if (
      entryResult.error ||
      !entryResult.data ||
      entryResult.data.length !== 1
    ) {
      return notFoundResponse();
    }

    const entry = entryResult.data[0];

    if (
      typeof entry !== "object" ||
      entry === null ||
      !("id" in entry) ||
      !("diary_id" in entry) ||
      !("author_participant_id" in entry) ||
      !("deleted_at" in entry) ||
      typeof entry.id !== "string" ||
      !isUuid(entry.id) ||
      entry.id.toLowerCase() !== canonicalEntryId ||
      typeof entry.diary_id !== "string" ||
      !isUuid(entry.diary_id) ||
      typeof entry.author_participant_id !== "string" ||
      !isUuid(entry.author_participant_id) ||
      entry.deleted_at !== null
    ) {
      return notFoundResponse();
    }

    const canonicalDiaryId = entry.diary_id.toLowerCase();
    const canonicalAuthorParticipantId =
      entry.author_participant_id.toLowerCase();
    const authorResult = await supabase
      .from("exchange_diary_participants")
      .select("id, diary_id, user_id")
      .eq("id", canonicalAuthorParticipantId)
      .eq("diary_id", canonicalDiaryId)
      .limit(2)
      .returns<unknown[]>();

    if (
      authorResult.error ||
      !authorResult.data ||
      authorResult.data.length !== 1
    ) {
      return notFoundResponse();
    }

    const author = authorResult.data[0];

    if (
      typeof author !== "object" ||
      author === null ||
      !("id" in author) ||
      !("diary_id" in author) ||
      !("user_id" in author) ||
      typeof author.id !== "string" ||
      !isUuid(author.id) ||
      author.id.toLowerCase() !== canonicalAuthorParticipantId ||
      typeof author.diary_id !== "string" ||
      !isUuid(author.diary_id) ||
      author.diary_id.toLowerCase() !== canonicalDiaryId ||
      typeof author.user_id !== "string" ||
      !isUuid(author.user_id)
    ) {
      return notFoundResponse();
    }

    if (
      !isExchangeEntryImageStoragePathFor(metadata.storage_path, {
        ownerUserId: author.user_id,
        diaryId: canonicalDiaryId,
        entryId: canonicalEntryId,
        imageId: canonicalImageId,
      })
    ) {
      return notFoundResponse();
    }

    const downloadResult = await supabase.storage
      .from(EXCHANGE_ENTRY_IMAGE_BUCKET)
      .download(metadata.storage_path, {}, { cache: "no-store" });
    const image = downloadResult.data;
    const contentType = image?.type.toLowerCase();

    if (
      downloadResult.error ||
      !image ||
      !contentType ||
      !allowedMimeTypes.has(contentType) ||
      image.size === 0 ||
      image.size > EXCHANGE_ENTRY_IMAGE_MAX_SIZE_BYTES
    ) {
      return notFoundResponse();
    }

    const detectedContentType = detectExchangeEntryImageMimeType(
      new Uint8Array(await image.slice(0, 12).arrayBuffer()),
    );

    if (!detectedContentType || detectedContentType !== contentType) {
      return notFoundResponse();
    }

    return new Response(image, {
      headers: {
        ...privateImageHeaders,
        "Content-Length": String(image.size),
        "Content-Type": detectedContentType,
      },
      status: 200,
    });
  } catch {
    return notFoundResponse();
  }
}
