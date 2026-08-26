import type { SupabaseClient } from "@supabase/supabase-js";

import { isPostMood, type PostMood } from "@/lib/post-data";

const RELATED_POST_LIMIT = 3;
const RELATED_POST_DATA_ERROR = new Error(
  "Related post data is invalid.",
);

export type RelatedPost = {
  id: string;
  user_id: string;
  authorUsername: string | null;
  created_at: string;
  title: string | null;
  body: string;
  mood: PostMood | null;
};

export type RelatedPostResult =
  | {
      data: RelatedPost[];
      error: null;
    }
  | {
      data: null;
      error: unknown;
    };

type RawRelatedPost = Omit<RelatedPost, "authorUsername">;

type RawTagRelatedPost = RawRelatedPost & {
  matching_tags: unknown;
};

type RawRelatedProfile = {
  user_id: string;
  username: string;
};

function isRawRelatedPost(value: unknown): value is RawRelatedPost {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("user_id" in value) ||
    !("created_at" in value) ||
    !("title" in value) ||
    !("body" in value) ||
    !("mood" in value) ||
    typeof value.id !== "string" ||
    typeof value.user_id !== "string" ||
    typeof value.created_at !== "string" ||
    (value.title !== null && typeof value.title !== "string") ||
    typeof value.body !== "string" ||
    (value.mood !== null &&
      (typeof value.mood !== "string" || !isPostMood(value.mood)))
  ) {
    return false;
  }

  return Number.isFinite(new Date(value.created_at).getTime());
}

function hasUniquePostIds(posts: readonly RawRelatedPost[]) {
  return new Set(posts.map((post) => post.id)).size === posts.length;
}

function hasCurrentPostTag(value: unknown, currentPostTagIds: Set<string>) {
  return (
    Array.isArray(value) &&
    value.some(
      (relation) =>
        typeof relation === "object" &&
        relation !== null &&
        "tag_id" in relation &&
        typeof relation.tag_id === "string" &&
        currentPostTagIds.has(relation.tag_id),
    )
  );
}

function isRawRelatedProfile(value: unknown): value is RawRelatedProfile {
  return (
    typeof value === "object" &&
    value !== null &&
    "user_id" in value &&
    "username" in value &&
    typeof value.user_id === "string" &&
    typeof value.username === "string" &&
    value.username.trim().length > 0
  );
}

export async function getRelatedPostsByAuthor(
  supabase: SupabaseClient,
  currentPostId: string,
  currentAuthorId: string,
): Promise<RelatedPostResult> {
  const result = await supabase
    .from("posts")
    .select("id, user_id, title, body, mood, created_at")
    .eq("user_id", currentAuthorId)
    .neq("id", currentPostId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(RELATED_POST_LIMIT)
    .returns<RawRelatedPost[]>();

  if (result.error || !result.data) {
    return {
      data: null,
      error: result.error ?? RELATED_POST_DATA_ERROR,
    };
  }

  if (
    !result.data.every(isRawRelatedPost) ||
    !hasUniquePostIds(result.data)
  ) {
    return { data: null, error: RELATED_POST_DATA_ERROR };
  }

  return {
    data: result.data.map((post) => ({
      ...post,
      authorUsername: null,
    })),
    error: null,
  };
}

export async function getRelatedPostsByTags(
  supabase: SupabaseClient,
  currentPostId: string,
  currentAuthorId: string,
  currentPostTagIds: readonly string[],
): Promise<RelatedPostResult> {
  const distinctTagIds = [...new Set(currentPostTagIds)];

  if (distinctTagIds.length === 0) {
    return { data: [], error: null };
  }

  const currentPostTagIdSet = new Set(distinctTagIds);
  const result = await supabase
    .from("posts")
    .select(
      "id, user_id, title, body, mood, created_at, matching_tags:post_tags!inner(tag_id)",
    )
    .in("matching_tags.tag_id", distinctTagIds)
    .neq("id", currentPostId)
    .neq("user_id", currentAuthorId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(RELATED_POST_LIMIT)
    .returns<RawTagRelatedPost[]>();

  if (result.error || !result.data) {
    return {
      data: null,
      error: result.error ?? RELATED_POST_DATA_ERROR,
    };
  }

  if (
    !result.data.every(
      (post) =>
        isRawRelatedPost(post) &&
        hasCurrentPostTag(post.matching_tags, currentPostTagIdSet),
    ) ||
    !hasUniquePostIds(result.data)
  ) {
    return { data: null, error: RELATED_POST_DATA_ERROR };
  }

  const posts = result.data.map((post) => {
    const { matching_tags: omittedMatchingTags, ...relatedPost } = post;
    void omittedMatchingTags;
    return relatedPost;
  });

  if (posts.length === 0) {
    return { data: [], error: null };
  }

  const authorIds = [...new Set(posts.map((post) => post.user_id))];
  const profilesResult = await supabase
    .from("profiles")
    .select("user_id, username")
    .in("user_id", authorIds)
    .returns<RawRelatedProfile[]>();

  if (
    profilesResult.error ||
    !profilesResult.data ||
    !profilesResult.data.every(isRawRelatedProfile)
  ) {
    return {
      data: null,
      error: profilesResult.error ?? RELATED_POST_DATA_ERROR,
    };
  }

  const usernamesByUserId = new Map(
    profilesResult.data.map((profile) => [
      profile.user_id,
      profile.username.trim(),
    ]),
  );

  if (
    authorIds.some((authorId) => !usernamesByUserId.get(authorId)) ||
    usernamesByUserId.size !== authorIds.length
  ) {
    return { data: null, error: RELATED_POST_DATA_ERROR };
  }

  return {
    data: posts.map((post) => ({
      ...post,
      authorUsername: usernamesByUserId.get(post.user_id) ?? null,
    })),
    error: null,
  };
}
