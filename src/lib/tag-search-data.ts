import type { SupabaseClient } from "@supabase/supabase-js";

import { isUuid } from "@/lib/profile-data";
import { encodeTagSearchCursor } from "@/lib/search-cursor";
import { validateSearchQuery } from "@/lib/search-query";

export const TAG_SEARCH_PAGE_SIZE = 20;

const TAG_SEARCH_SHAPE_ERROR = new Error(
  "Tag search result shape is invalid.",
);

export type TagSearchResultRow = {
  id: string;
  name: string;
  normalized_name: string;
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function isTagSearchResultRow(value: unknown): value is TagSearchResultRow {
  if (
    typeof value !== "object" ||
    value === null ||
    !hasExactKeys(value, ["id", "name", "normalized_name"]) ||
    !("id" in value) ||
    !("name" in value) ||
    !("normalized_name" in value) ||
    typeof value.id !== "string" ||
    typeof value.name !== "string" ||
    typeof value.normalized_name !== "string"
  ) {
    return false;
  }

  const validation = validateSearchQuery("tags", value.normalized_name);

  return (
    isUuid(value.id) &&
    value.name === value.normalized_name &&
    validation.error === null &&
    !validation.isEmpty &&
    validation.query === value.normalized_name
  );
}

export async function searchTags(
  supabase: SupabaseClient,
  query: string,
  afterNormalizedName: string | null,
) {
  const result = await supabase
    .rpc("my_diary_search_tags", {
      search_query: query,
      after_normalized_name: afterNormalizedName,
    })
    .returns<unknown[]>();

  if (result.error || !result.data) {
    return { data: null, nextCursor: null, error: result.error };
  }

  const rawRows: unknown = result.data;

  if (
    !Array.isArray(rawRows) ||
    rawRows.length > TAG_SEARCH_PAGE_SIZE + 1 ||
    !rawRows.every(isTagSearchResultRow)
  ) {
    return { data: null, nextCursor: null, error: TAG_SEARCH_SHAPE_ERROR };
  }

  const tags = rawRows.slice(0, TAG_SEARCH_PAGE_SIZE);
  const lastTag = tags.at(-1);
  const nextCursor =
    rawRows.length > TAG_SEARCH_PAGE_SIZE && lastTag
      ? encodeTagSearchCursor({
          q: query,
          afterNormalizedName: lastTag.normalized_name,
        })
      : null;

  return { data: tags, nextCursor, error: null };
}
