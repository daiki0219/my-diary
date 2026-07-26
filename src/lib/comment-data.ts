import type { SupabaseClient } from "@supabase/supabase-js";

export const COMMENT_MAX_LENGTH = 1000;
export const COMMENT_LIST_LIMIT = 100;

const COMMENT_COUNT_PAGE_SIZE = 1000;

export type Comment = {
  id: string;
  user_id: string;
  body: string;
  created_at: string;
  author: {
    username: string;
  } | null;
};

type CommentRow = Omit<Comment, "author">;

export async function getCommentCounts(
  supabase: SupabaseClient,
  postIds: string[],
) {
  const counts = new Map<string, number>(
    postIds.map((postId) => [postId, 0]),
  );

  if (postIds.length === 0) {
    return { data: counts, error: null };
  }

  let offset = 0;

  while (true) {
    const result = await supabase
      .from("comments")
      .select("post_id")
      .in("post_id", postIds)
      .order("post_id", { ascending: true })
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(offset, offset + COMMENT_COUNT_PAGE_SIZE - 1)
      .returns<Array<{ post_id: string }>>();

    if (result.error || !result.data) {
      return { data: null, error: result.error };
    }

    for (const comment of result.data) {
      counts.set(comment.post_id, (counts.get(comment.post_id) ?? 0) + 1);
    }

    if (result.data.length < COMMENT_COUNT_PAGE_SIZE) {
      return { data: counts, error: null };
    }

    offset += COMMENT_COUNT_PAGE_SIZE;
  }
}

export async function getCommentsForPost(
  supabase: SupabaseClient,
  postId: string,
) {
  const commentsResult = await supabase
    .from("comments")
    .select("id, user_id, body, created_at", { count: "exact" })
    .eq("post_id", postId)
    .order("created_at", { ascending: true })
    .order("id", { ascending: true })
    .range(0, COMMENT_LIST_LIMIT - 1)
    .returns<CommentRow[]>();

  if (
    commentsResult.error ||
    !commentsResult.data ||
    commentsResult.count === null
  ) {
    return {
      data: null,
      total: null,
      isTruncated: false,
      error: commentsResult.error,
    };
  }

  const authorIds = [
    ...new Set(commentsResult.data.map((comment) => comment.user_id)),
  ];
  const profilesResult =
    authorIds.length > 0
      ? await supabase
          .from("profiles")
          .select("user_id, username")
          .in("user_id", authorIds)
          .returns<Array<{ user_id: string; username: string }>>()
      : { data: [], error: null };

  if (profilesResult.error || !profilesResult.data) {
    return {
      data: null,
      total: null,
      isTruncated: false,
      error: profilesResult.error,
    };
  }

  const profilesByUserId = new Map(
    profilesResult.data.map((profile) => [
      profile.user_id,
      { username: profile.username },
    ]),
  );

  return {
    data: commentsResult.data.map((comment) => ({
      ...comment,
      author: profilesByUserId.get(comment.user_id) ?? null,
    })),
    total: commentsResult.count,
    isTruncated: commentsResult.count > COMMENT_LIST_LIMIT,
    error: null,
  };
}
