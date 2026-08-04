import type { SupabaseClient } from "@supabase/supabase-js";

import {
  attachPostTags,
  hydrateTimelinePosts,
  type PostMood,
  type PostVisibility,
  type RawTagRelations,
} from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
import { validateTagInputValues } from "@/lib/tag-data";

export const TAG_LIST_PAGE_SIZE = 50;
export const TAG_POST_PAGE_SIZE = 20;

const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;
const TAG_PAGE_RELATION_ERROR = new Error(
  "Tag page relation shape is invalid.",
);

export type VisibleTag = {
  id: string;
  name: string;
  normalized_name: string;
};

export type TagListCursor = {
  normalized_name: string;
};

export type TagPostCursor = {
  created_at: string;
  id: string;
};

type RawTagPostRow = {
  id: string;
  user_id: string;
  title: string | null;
  body: string;
  mood: PostMood | null;
  visibility: PostVisibility;
  created_at: string;
  matching_tags: unknown;
} & RawTagRelations;

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function encodeOpaqueCursor(value: object) {
  return Buffer.from(JSON.stringify(value), "utf8").toString("base64url");
}

function decodeOpaqueCursor(value: string): unknown | null {
  if (
    value.length === 0 ||
    value.length > CURSOR_MAX_LENGTH ||
    !CURSOR_CHARACTER_PATTERN.test(value)
  ) {
    return null;
  }

  try {
    const bytes = Buffer.from(value, "base64url");

    if (bytes.toString("base64url") !== value) {
      return null;
    }

    const json = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return JSON.parse(json) as unknown;
  } catch {
    return null;
  }
}

function isCanonicalTagName(value: string) {
  const result = validateTagInputValues([value]);
  return result.error === null && result.data[0] === value;
}

function canonicalizeTimestamp(value: string) {
  const date = new Date(value);

  if (!Number.isFinite(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

export function encodeTagListCursor(cursor: TagListCursor) {
  if (!isCanonicalTagName(cursor.normalized_name)) {
    throw new Error("Cannot encode an invalid tag list cursor.");
  }

  return encodeOpaqueCursor(cursor);
}

export function decodeTagListCursor(value: string): TagListCursor | null {
  const cursor = decodeOpaqueCursor(value);

  if (
    typeof cursor !== "object" ||
    cursor === null ||
    !hasExactKeys(cursor, ["normalized_name"]) ||
    !("normalized_name" in cursor) ||
    typeof cursor.normalized_name !== "string" ||
    !isCanonicalTagName(cursor.normalized_name)
  ) {
    return null;
  }

  return { normalized_name: cursor.normalized_name };
}

export function encodeTagPostCursor(cursor: TagPostCursor) {
  const createdAt = canonicalizeTimestamp(cursor.created_at);

  if (!createdAt || !isUuid(cursor.id)) {
    throw new Error("Cannot encode an invalid tag post cursor.");
  }

  return encodeOpaqueCursor({
    created_at: createdAt,
    id: cursor.id.toLowerCase(),
  });
}

export function decodeTagPostCursor(value: string): TagPostCursor | null {
  const cursor = decodeOpaqueCursor(value);

  if (
    typeof cursor !== "object" ||
    cursor === null ||
    !hasExactKeys(cursor, ["created_at", "id"]) ||
    !("created_at" in cursor) ||
    !("id" in cursor) ||
    typeof cursor.created_at !== "string" ||
    typeof cursor.id !== "string" ||
    cursor.id !== cursor.id.toLowerCase() ||
    !isUuid(cursor.id)
  ) {
    return null;
  }

  const createdAt = canonicalizeTimestamp(cursor.created_at);

  if (!createdAt || createdAt !== cursor.created_at) {
    return null;
  }

  return { created_at: createdAt, id: cursor.id };
}

function isVisibleTag(value: unknown): value is VisibleTag {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("name" in value) ||
    !("normalized_name" in value) ||
    typeof value.id !== "string" ||
    typeof value.name !== "string" ||
    typeof value.normalized_name !== "string"
  ) {
    return false;
  }

  return (
    isUuid(value.id) &&
    value.name === value.normalized_name &&
    isCanonicalTagName(value.normalized_name)
  );
}

export async function getVisibleTags(
  supabase: SupabaseClient,
  cursor: TagListCursor | null,
) {
  let query = supabase
    .from("tags")
    .select("id, name, normalized_name")
    .order("normalized_name", { ascending: true })
    .limit(TAG_LIST_PAGE_SIZE + 1);

  if (cursor) {
    query = query.gt("normalized_name", cursor.normalized_name);
  }

  const result = await query.returns<VisibleTag[]>();

  if (result.error || !result.data) {
    return { data: null, nextCursor: null, error: result.error };
  }

  if (!result.data.every(isVisibleTag)) {
    return { data: null, nextCursor: null, error: TAG_PAGE_RELATION_ERROR };
  }

  const tags = result.data.slice(0, TAG_LIST_PAGE_SIZE);
  const lastTag = tags.at(-1);
  const nextCursor =
    result.data.length > TAG_LIST_PAGE_SIZE && lastTag
      ? encodeTagListCursor({ normalized_name: lastTag.normalized_name })
      : null;

  return { data: tags, nextCursor, error: null };
}

export async function getVisibleTag(
  supabase: SupabaseClient,
  tagId: string,
) {
  const result = await supabase
    .from("tags")
    .select("id, name, normalized_name")
    .eq("id", tagId)
    .limit(1)
    .maybeSingle<VisibleTag>();

  if (result.error) {
    return { data: null, error: result.error };
  }

  if (result.data && !isVisibleTag(result.data)) {
    return { data: null, error: TAG_PAGE_RELATION_ERROR };
  }

  return { data: result.data, error: null };
}

function hasMatchingTag(value: unknown, tagId: string) {
  return (
    Array.isArray(value) &&
    value.some(
      (relation) =>
        typeof relation === "object" &&
        relation !== null &&
        "tag_id" in relation &&
        relation.tag_id === tagId,
    )
  );
}

export async function getVisiblePostsForTag(
  supabase: SupabaseClient,
  tagId: string,
  currentUserId: string,
  cursor: TagPostCursor | null,
) {
  let query = supabase
    .from("posts")
    .select(
      "id, user_id, title, body, mood, visibility, created_at, matching_tags:post_tags!inner(tag_id), post_tags(tags(id, name))",
    )
    .eq("matching_tags.tag_id", tagId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(TAG_POST_PAGE_SIZE + 1);

  if (cursor) {
    query = query.or(
      `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`,
    );
  }

  const result = await query.returns<RawTagPostRow[]>();

  if (result.error || !result.data) {
    return {
      data: null,
      nextCursor: null,
      error: result.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  if (!result.data.every((post) => hasMatchingTag(post.matching_tags, tagId))) {
    return {
      data: null,
      nextCursor: null,
      error: TAG_PAGE_RELATION_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const loadedPosts = attachPostTags(result.data);

  if (!loadedPosts) {
    return {
      data: null,
      nextCursor: null,
      error: TAG_PAGE_RELATION_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const posts = loadedPosts.slice(0, TAG_POST_PAGE_SIZE).map((post) => {
    const { matching_tags: omittedMatchingTags, ...visiblePost } = post;
    void omittedMatchingTags;
    return visiblePost;
  });
  const hydrationResult = await hydrateTimelinePosts(
    supabase,
    posts,
    currentUserId,
  );
  const lastPost = posts.at(-1);
  const nextCursor =
    loadedPosts.length > TAG_POST_PAGE_SIZE && lastPost
      ? encodeTagPostCursor({
          created_at: lastPost.created_at,
          id: lastPost.id,
        })
      : null;

  return { ...hydrationResult, nextCursor };
}
