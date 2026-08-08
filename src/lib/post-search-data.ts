import type { SupabaseClient } from "@supabase/supabase-js";

import {
  attachPostTags,
  hydrateTimelinePosts,
  isPostMood,
  isPostVisibility,
  type RawTagRelations,
  type TimelinePost,
} from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
import {
  comparePostSearchRows,
  encodePostSearchCursor,
  isPostSearchTimestamp,
} from "@/lib/search-cursor";

export const POST_SEARCH_PAGE_SIZE = 20;

const POST_SEARCH_SHAPE_ERROR = new Error(
  "Post search result shape is invalid.",
);

type PostSearchRpcRow = {
  id: string;
  created_at: string;
};

type RawPostSearchPost = Omit<
  TimelinePost,
  "author" | "images" | "reactions" | "commentCount" | "tags"
> &
  RawTagRelations;

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function isLowercaseUuid(value: string) {
  return isUuid(value) && value === value.toLowerCase();
}

function isPostSearchRpcRow(value: unknown): value is PostSearchRpcRow {
  return (
    typeof value === "object" &&
    value !== null &&
    hasExactKeys(value, ["id", "created_at"]) &&
    "id" in value &&
    "created_at" in value &&
    typeof value.id === "string" &&
    isLowercaseUuid(value.id) &&
    typeof value.created_at === "string" &&
    isPostSearchTimestamp(value.created_at)
  );
}

function isRawPostSearchPost(value: unknown): value is RawPostSearchPost {
  return (
    typeof value === "object" &&
    value !== null &&
    hasExactKeys(value, [
      "id",
      "user_id",
      "title",
      "body",
      "mood",
      "visibility",
      "created_at",
      "post_tags",
    ]) &&
    "id" in value &&
    "user_id" in value &&
    "title" in value &&
    "body" in value &&
    "mood" in value &&
    "visibility" in value &&
    "created_at" in value &&
    "post_tags" in value &&
    typeof value.id === "string" &&
    isLowercaseUuid(value.id) &&
    typeof value.user_id === "string" &&
    isLowercaseUuid(value.user_id) &&
    (value.title === null || typeof value.title === "string") &&
    typeof value.body === "string" &&
    (value.mood === null ||
      (typeof value.mood === "string" && isPostMood(value.mood))) &&
    typeof value.visibility === "string" &&
    isPostVisibility(value.visibility) &&
    typeof value.created_at === "string" &&
    isPostSearchTimestamp(value.created_at)
  );
}

function hasValidRpcOrder(rows: readonly PostSearchRpcRow[]) {
  const ids = new Set<string>();

  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index];

    if (ids.has(row.id)) {
      return false;
    }

    ids.add(row.id);

    if (
      index > 0 &&
      comparePostSearchRows(rows[index - 1], row) >= 0
    ) {
      return false;
    }
  }

  return true;
}

export async function searchPosts(
  supabase: SupabaseClient,
  query: string,
  beforeCreatedAt: string | null,
  beforeId: string | null,
  currentUserId: string,
) {
  const rpcResult = await supabase
    .rpc("my_diary_search_posts", {
      search_query: query,
      before_created_at: beforeCreatedAt,
      before_id: beforeId,
    })
    .returns<unknown[]>();

  if (rpcResult.error || !rpcResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: rpcResult.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  const rawRows: unknown = rpcResult.data;

  if (
    !Array.isArray(rawRows) ||
    rawRows.length > POST_SEARCH_PAGE_SIZE + 1 ||
    !rawRows.every(isPostSearchRpcRow) ||
    !hasValidRpcOrder(rawRows)
  ) {
    return {
      data: null,
      nextCursor: null,
      error: POST_SEARCH_SHAPE_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const displayRows = rawRows.slice(0, POST_SEARCH_PAGE_SIZE);
  const boundary = displayRows.at(-1);
  const nextCursor =
    rawRows.length > POST_SEARCH_PAGE_SIZE && boundary
      ? encodePostSearchCursor({
          q: query,
          beforeCreatedAt: boundary.created_at,
          beforeId: boundary.id,
        })
      : null;

  if (displayRows.length === 0) {
    return {
      data: [],
      nextCursor,
      error: null,
      reactionsError: null,
      commentsError: null,
    };
  }

  const displayIds = displayRows.map((row) => row.id);
  const postsResult = await supabase
    .from("posts")
    .select(
      "id, user_id, title, body, mood, visibility, created_at, post_tags(tags(id, name))",
    )
    .in("id", displayIds)
    .returns<unknown[]>();

  if (postsResult.error || !postsResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: postsResult.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  const rawPosts: unknown = postsResult.data;

  if (
    !Array.isArray(rawPosts) ||
    rawPosts.length > displayRows.length ||
    !rawPosts.every(isRawPostSearchPost)
  ) {
    return {
      data: null,
      nextCursor: null,
      error: POST_SEARCH_SHAPE_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const allowedIds = new Set(displayIds);
  const loadedIds = new Set<string>();

  for (const post of rawPosts) {
    if (!allowedIds.has(post.id) || loadedIds.has(post.id)) {
      return {
        data: null,
        nextCursor: null,
        error: POST_SEARCH_SHAPE_ERROR,
        reactionsError: null,
        commentsError: null,
      };
    }

    loadedIds.add(post.id);
  }

  const posts = attachPostTags(rawPosts);

  if (!posts) {
    return {
      data: null,
      nextCursor: null,
      error: POST_SEARCH_SHAPE_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const rpcRowsById = new Map(displayRows.map((row) => [row.id, row]));
  const postsById = new Map(
    posts
      .filter((post) => {
        const rpcRow = rpcRowsById.get(post.id);
        return rpcRow?.created_at === post.created_at;
      })
      .map((post) => [post.id, post]),
  );
  const orderedPosts = displayRows.flatMap((row) => {
    const post = postsById.get(row.id);
    return post ? [post] : [];
  });

  if (orderedPosts.length === 0) {
    return {
      data: [],
      nextCursor,
      error: null,
      reactionsError: null,
      commentsError: null,
    };
  }

  const hydrationResult = await hydrateTimelinePosts(
    supabase,
    orderedPosts,
    currentUserId,
  );

  return {
    ...hydrationResult,
    nextCursor,
  };
}
