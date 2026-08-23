import type { SupabaseClient } from "@supabase/supabase-js";

export const COMMENT_MAX_LENGTH = 1000;
export const COMMENT_LIST_LIMIT = 100;

const COMMENT_COUNT_PAGE_SIZE = 1000;
const TIMELINE_COMMENT_PREVIEW_LIMIT = 2;
const TIMELINE_COMMENT_PREVIEW_DATA_ERROR = new Error(
  "Timeline comment preview data is invalid.",
);

export type Comment = {
  id: string;
  user_id: string;
  parent_comment_id: string | null;
  body: string;
  created_at: string;
  author: {
    username: string;
  } | null;
};

type CommentRow = Omit<Comment, "author">;

type TimelineCommentPreviewRow = Pick<
  Comment,
  "id" | "user_id" | "body" | "created_at"
>;

type TimelineCommentPreviewPostRow = {
  id: string;
  comment_previews: TimelineCommentPreviewRow[];
};

export type TimelineCommentPreview = {
  id: string;
  authorUsername: string;
  body: string;
};

export type DisplayComment = Omit<Comment, "parent_comment_id">;

export type CommentThread =
  | {
      kind: "available";
      parent: DisplayComment;
      replies: DisplayComment[];
    }
  | {
      kind: "unavailable";
      key: string;
      replies: DisplayComment[];
    };

function compareComments(
  left: Pick<Comment, "created_at" | "id">,
  right: Pick<Comment, "created_at" | "id">,
) {
  const createdAtComparison = left.created_at.localeCompare(right.created_at);

  return createdAtComparison !== 0
    ? createdAtComparison
    : left.id.localeCompare(right.id);
}

function toDisplayComment(comment: Comment): DisplayComment {
  return {
    id: comment.id,
    user_id: comment.user_id,
    body: comment.body,
    created_at: comment.created_at,
    author: comment.author,
  };
}

export function buildCommentThreads(comments: Comment[]): CommentThread[] {
  const topLevelComments = comments
    .filter((comment) => comment.parent_comment_id === null)
    .sort(compareComments);
  const topLevelIds = new Set(topLevelComments.map((comment) => comment.id));
  const repliesByParentId = new Map<string, Comment[]>();

  for (const comment of comments) {
    if (comment.parent_comment_id === null) {
      continue;
    }

    const replies = repliesByParentId.get(comment.parent_comment_id) ?? [];
    replies.push(comment);
    repliesByParentId.set(comment.parent_comment_id, replies);
  }

  const threads: Array<{
    sortComment: Pick<Comment, "created_at" | "id">;
    thread: CommentThread;
  }> = topLevelComments.map((parent) => ({
    sortComment: parent,
    thread: {
      kind: "available",
      parent: toDisplayComment(parent),
      replies: (repliesByParentId.get(parent.id) ?? [])
        .sort(compareComments)
        .map(toDisplayComment),
    },
  }));

  for (const [parentId, replies] of repliesByParentId) {
    if (topLevelIds.has(parentId)) {
      continue;
    }

    const sortedReplies = replies.sort(compareComments);
    const firstReply = sortedReplies[0];

    if (!firstReply) {
      continue;
    }

    threads.push({
      sortComment: firstReply,
      thread: {
        kind: "unavailable",
        key: `unavailable-${firstReply.id}`,
        replies: sortedReplies.map(toDisplayComment),
      },
    });
  }

  return threads
    .sort((left, right) =>
      compareComments(left.sortComment, right.sortComment),
    )
    .map(({ thread }) => thread);
}

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

export async function getTimelineCommentPreviews(
  supabase: SupabaseClient,
  postIds: string[],
) {
  const previewsByPostId = new Map<string, TimelineCommentPreview[]>(
    postIds.map((postId) => [postId, []]),
  );

  if (postIds.length === 0) {
    return { data: previewsByPostId, error: null };
  }

  const commentsResult = await supabase
    .from("posts")
    .select(
      "id, comment_previews:comments!my_diary_comments_post_id_fkey(id, user_id, body, created_at)",
    )
    .in("id", postIds)
    .is("comment_previews.parent_comment_id", null)
    .is("comment_previews.deleted_at", null)
    .order("created_at", {
      ascending: false,
      referencedTable: "comment_previews",
    })
    .order("id", {
      ascending: false,
      referencedTable: "comment_previews",
    })
    .limit(TIMELINE_COMMENT_PREVIEW_LIMIT, {
      referencedTable: "comment_previews",
    })
    .returns<TimelineCommentPreviewPostRow[]>();

  if (commentsResult.error || !commentsResult.data) {
    return { data: null, error: commentsResult.error };
  }

  if (
    commentsResult.data.some(
      (post) =>
        !postIds.includes(post.id) ||
        !Array.isArray(post.comment_previews) ||
        post.comment_previews.length > TIMELINE_COMMENT_PREVIEW_LIMIT,
    )
  ) {
    return { data: null, error: TIMELINE_COMMENT_PREVIEW_DATA_ERROR };
  }

  const authorIds = [
    ...new Set(
      commentsResult.data.flatMap((post) =>
        post.comment_previews.map((comment) => comment.user_id),
      ),
    ),
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
    return { data: null, error: profilesResult.error };
  }

  const usernamesByUserId = new Map(
    profilesResult.data.map((profile) => [
      profile.user_id,
      profile.username.trim(),
    ]),
  );

  for (const post of commentsResult.data) {
    previewsByPostId.set(
      post.id,
      [...post.comment_previews]
        .reverse()
        .flatMap((comment) => {
          const authorUsername = usernamesByUserId.get(comment.user_id);

          return authorUsername
            ? [
                {
                  id: comment.id,
                  authorUsername,
                  body: comment.body,
                },
              ]
            : [];
        }),
    );
  }

  return { data: previewsByPostId, error: null };
}

export async function getCommentsForPost(
  supabase: SupabaseClient,
  postId: string,
) {
  const commentsResult = await supabase
    .from("comments")
    .select("id, user_id, parent_comment_id, body, created_at", {
      count: "exact",
    })
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
