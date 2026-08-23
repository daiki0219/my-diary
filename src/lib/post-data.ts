import type { SupabaseClient } from "@supabase/supabase-js";

import {
  getCommentCounts,
  getTimelineCommentPreviews,
} from "@/lib/comment-data";
import {
  getPostImagesByPostIds,
  type PostImageReference,
} from "@/lib/post-image-data";
import {
  getReactionSummaries,
  type ReactionSummary,
} from "@/lib/reaction-data";
import {
  compareCanonicalTagNames,
  type PostTag,
} from "@/lib/tag-data";
import {
  encodeTimelineCursor,
  type TimelineCursor,
  type TimelineCursorFeed,
} from "@/lib/timeline-cursor";

export const POST_MOODS = [
  "happy",
  "sad",
  "tired",
  "irritated",
  "calm",
  "neutral",
] as const;

export type PostMood = (typeof POST_MOODS)[number];

export const POST_VISIBILITIES = [
  "private",
  "followers",
  "public",
] as const;

export type PostVisibility = (typeof POST_VISIBILITIES)[number];

export type TimelineFeed = TimelineCursorFeed;

export const POST_MOOD_OPTIONS: ReadonlyArray<{
  value: PostMood;
  label: string;
}> = [
  { value: "happy", label: "😊 楽しい" },
  { value: "sad", label: "😢 悲しい" },
  { value: "tired", label: "😴 疲れた" },
  { value: "irritated", label: "😡 イライラ" },
  { value: "calm", label: "😌 穏やか" },
  { value: "neutral", label: "😐 普通" },
];

export const POST_VISIBILITY_OPTIONS: ReadonlyArray<{
  value: PostVisibility;
  label: string;
}> = [
  { value: "private", label: "非公開" },
  { value: "followers", label: "フォロワーのみ" },
  { value: "public", label: "公開" },
];

export type Post = {
  id: string;
  title: string | null;
  body: string;
  mood: PostMood | null;
  location_name: string | null;
  visibility: PostVisibility;
  created_at: string;
  images: PostImageReference[];
  tags: PostTag[];
  reactions: ReactionSummary | null;
  commentCount: number | null;
};

export type TimelinePost = Post & {
  user_id: string;
  author: {
    username: string;
  } | null;
};

export type PostDetail = Omit<TimelinePost, "commentCount">;

export type EditablePost = Pick<
  PostDetail,
  | "id"
  | "title"
  | "body"
  | "mood"
  | "location_name"
  | "visibility"
  | "tags"
  | "images"
>;

export type PostDetailResult =
  | {
      status: "found";
      post: PostDetail;
    }
  | {
      status: "not-found";
    }
  | {
      status: "error";
    };

const USER_PROFILE_POST_LIMIT = 20;
export const TIMELINE_PAGE_SIZE = 20;
const TAG_RELATION_LOAD_ERROR = new Error("Post tag relation shape is invalid.");
const TIMELINE_DATA_ERROR = new Error("Timeline data is invalid.");

export type RawTagRelations = {
  post_tags: unknown;
};

export function parsePostTags(value: unknown): PostTag[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const tags: PostTag[] = [];

  for (const relation of value) {
    if (
      typeof relation !== "object" ||
      relation === null ||
      !("tags" in relation) ||
      typeof relation.tags !== "object" ||
      relation.tags === null ||
      !("id" in relation.tags) ||
      typeof relation.tags.id !== "string" ||
      !("name" in relation.tags) ||
      typeof relation.tags.name !== "string"
    ) {
      return null;
    }

    tags.push({ id: relation.tags.id, name: relation.tags.name });
  }

  return tags.sort((left, right) =>
    compareCanonicalTagNames(left.name, right.name),
  );
}

export function attachPostTags<T extends RawTagRelations>(rows: readonly T[]) {
  const posts: Array<Omit<T, "post_tags"> & { tags: PostTag[] }> = [];

  for (const row of rows) {
    const tags = parsePostTags(row.post_tags);

    if (!tags) {
      return null;
    }

    const { post_tags: omittedPostTags, ...post } = row;
    void omittedPostTags;
    posts.push({ ...post, tags });
  }

  return posts;
}

export async function getOwnPosts(
  supabase: SupabaseClient,
  userId: string,
) {
  const postsResult = await supabase
    .from("posts")
    .select(
      "id, title, body, mood, location_name, visibility, created_at, post_tags(tags(id, name))",
    )
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .returns<
      Array<
        Omit<Post, "images" | "reactions" | "commentCount" | "tags"> &
          RawTagRelations
      >
    >();

  if (postsResult.error || !postsResult.data) {
    return {
      data: null,
      error: postsResult.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  const posts = attachPostTags(postsResult.data);

  if (!posts) {
    return {
      data: null,
      error: TAG_RELATION_LOAD_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const postIds = posts.map((post) => post.id);
  const [reactionsResult, commentsResult, imagesResult] = await Promise.all([
    getReactionSummaries(supabase, postIds, userId),
    getCommentCounts(supabase, postIds),
    getPostImagesByPostIds(supabase, postIds),
  ]);

  if (imagesResult.error || !imagesResult.data) {
    return {
      data: null,
      error: imagesResult.error,
      reactionsError: reactionsResult.error,
      commentsError: commentsResult.error,
    };
  }

  return {
    data: posts.map((post) => ({
      ...post,
      images: imagesResult.data?.get(post.id) ?? [],
      reactions: reactionsResult.data?.get(post.id) ?? null,
      commentCount: commentsResult.data?.get(post.id) ?? null,
    })),
    error: null,
    reactionsError: reactionsResult.error,
    commentsError: commentsResult.error,
  };
}

export async function getVisiblePostsByUser(
  supabase: SupabaseClient,
  targetUserId: string,
  currentUserId: string,
) {
  const postsResult = await supabase
    .from("posts")
    .select(
      "id, title, body, mood, location_name, visibility, created_at, post_tags(tags(id, name))",
    )
    .eq("user_id", targetUserId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(USER_PROFILE_POST_LIMIT + 1)
    .returns<
      Array<
        Omit<Post, "images" | "reactions" | "commentCount" | "tags"> &
          RawTagRelations
      >
    >();

  if (postsResult.error || !postsResult.data) {
    return {
      data: null,
      hasMore: false,
      error: postsResult.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  const loadedPosts = attachPostTags(postsResult.data);

  if (!loadedPosts) {
    return {
      data: null,
      hasMore: false,
      error: TAG_RELATION_LOAD_ERROR,
      reactionsError: null,
      commentsError: null,
    };
  }

  const posts = loadedPosts.slice(0, USER_PROFILE_POST_LIMIT);
  const postIds = posts.map((post) => post.id);
  const [reactionsResult, commentsResult, imagesResult] = await Promise.all([
    getReactionSummaries(supabase, postIds, currentUserId),
    getCommentCounts(supabase, postIds),
    getPostImagesByPostIds(supabase, postIds),
  ]);

  if (imagesResult.error || !imagesResult.data) {
    return {
      data: null,
      hasMore: false,
      error: imagesResult.error,
      reactionsError: reactionsResult.error,
      commentsError: commentsResult.error,
    };
  }

  return {
    data: posts.map((post) => ({
      ...post,
      images: imagesResult.data?.get(post.id) ?? [],
      reactions: reactionsResult.data?.get(post.id) ?? null,
      commentCount: commentsResult.data?.get(post.id) ?? null,
    })),
    hasMore: loadedPosts.length > USER_PROFILE_POST_LIMIT,
    error: null,
    reactionsError: reactionsResult.error,
    commentsError: commentsResult.error,
  };
}

export async function getTimelinePosts(
  supabase: SupabaseClient,
  currentUserId: string,
  feed: TimelineFeed,
  cursor: TimelineCursor | null,
) {
  if (cursor && cursor.feed !== feed) {
    return {
      data: null,
      nextCursor: null,
      error: TIMELINE_DATA_ERROR,
      reactionsError: null,
      commentsError: null,
      commentPreviews: null,
      commentPreviewsError: null,
    };
  }

  let postsQuery = supabase
    .from("posts")
    .select(
      "id, user_id, title, body, mood, location_name, visibility, created_at, post_tags(tags(id, name))",
    )
    .is("deleted_at", null);

  if (feed === "following") {
    const followsResult = await supabase
      .from("follows")
      .select("following_id")
      .eq("follower_id", currentUserId)
      .returns<Array<{ following_id: string }>>();

    if (followsResult.error || !followsResult.data) {
      return {
        data: null,
        nextCursor: null,
        error: followsResult.error,
        reactionsError: null,
        commentsError: null,
        commentPreviews: null,
        commentPreviewsError: null,
      };
    }

    const authorIds = [
      ...new Set([
        currentUserId,
        ...followsResult.data.map((follow) => follow.following_id),
      ]),
    ];
    postsQuery = postsQuery.in("user_id", authorIds);
  } else {
    postsQuery = postsQuery.eq("visibility", "public");
  }

  if (cursor) {
    postsQuery = postsQuery.or(
      `created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`,
    );
  }

  const postsResult = await postsQuery
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(TIMELINE_PAGE_SIZE + 1)
    .returns<
      Array<
        Omit<
          TimelinePost,
          "author" | "images" | "reactions" | "commentCount" | "tags"
        > &
          RawTagRelations
      >
    >();

  if (postsResult.error || !postsResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: postsResult.error,
      reactionsError: null,
      commentsError: null,
      commentPreviews: null,
      commentPreviewsError: null,
    };
  }

  const posts = attachPostTags(postsResult.data);

  if (!posts) {
    return {
      data: null,
      nextCursor: null,
      error: TAG_RELATION_LOAD_ERROR,
      reactionsError: null,
      commentsError: null,
      commentPreviews: null,
      commentPreviewsError: null,
    };
  }

  const visiblePosts = posts.slice(0, TIMELINE_PAGE_SIZE);
  const postIds = visiblePosts.map((post) => post.id);
  const [hydrationResult, commentPreviewsResult] = await Promise.all([
    hydrateTimelinePosts(supabase, visiblePosts, currentUserId),
    getTimelineCommentPreviews(supabase, postIds).catch(() => ({
      data: null,
      error: new Error("Timeline comment previews could not be loaded."),
    })),
  ]);
  const lastPost = visiblePosts.at(-1);
  const nextCursor =
    posts.length > TIMELINE_PAGE_SIZE && lastPost
      ? encodeTimelineCursor({
          feed,
          createdAt: lastPost.created_at,
          id: lastPost.id,
        })
      : null;

  return {
    ...hydrationResult,
    nextCursor,
    commentPreviews: commentPreviewsResult.data,
    commentPreviewsError: commentPreviewsResult.error,
  };
}

export async function hydrateTimelinePosts(
  supabase: SupabaseClient,
  posts: ReadonlyArray<
    Omit<TimelinePost, "author" | "images" | "reactions" | "commentCount">
  >,
  currentUserId: string,
) {
  const authorIds = [...new Set(posts.map((post) => post.user_id))];
  const postIds = posts.map((post) => post.id);
  const [profilesResult, reactionsResult, commentsResult, imagesResult] =
    await Promise.all([
      authorIds.length > 0
        ? supabase
            .from("profiles")
            .select("user_id, username")
            .in("user_id", authorIds)
            .returns<Array<{ user_id: string; username: string }>>()
        : Promise.resolve({ data: [], error: null }),
      getReactionSummaries(supabase, postIds, currentUserId),
      getCommentCounts(supabase, postIds),
      getPostImagesByPostIds(supabase, postIds),
    ]);

  if (imagesResult.error || !imagesResult.data) {
    return {
      data: null,
      error: imagesResult.error,
      reactionsError: reactionsResult.error,
      commentsError: commentsResult.error,
    };
  }

  const profilesByUserId = new Map(
    (profilesResult.data ?? []).map((profile) => [
      profile.user_id,
      { username: profile.username },
    ]),
  );

  return {
    data: posts.map((post) => ({
      ...post,
      author: profilesByUserId.get(post.user_id) ?? null,
      images: imagesResult.data?.get(post.id) ?? [],
      reactions: reactionsResult.data?.get(post.id) ?? null,
      commentCount: commentsResult.data?.get(post.id) ?? null,
    })),
    error: profilesResult.error,
    reactionsError: reactionsResult.error,
    commentsError: commentsResult.error,
  };
}

export async function getPostDetail(
  supabase: SupabaseClient,
  postId: string,
  currentUserId: string,
): Promise<PostDetailResult> {
  const postsResult = await supabase
    .from("posts")
    .select(
      "id, user_id, title, body, mood, location_name, visibility, created_at, post_tags(tags(id, name))",
    )
    .eq("id", postId)
    .is("deleted_at", null)
    .limit(1)
    .returns<
      Array<
        Omit<PostDetail, "author" | "images" | "reactions" | "tags"> &
          RawTagRelations
      >
    >();

  if (postsResult.error || !postsResult.data) {
    return { status: "error" };
  }

  const rawPost = postsResult.data[0];

  if (!rawPost) {
    return { status: "not-found" };
  }

  const post = attachPostTags([rawPost])?.[0];

  if (!post) {
    return { status: "error" };
  }

  const [profileResult, reactionsResult, imagesResult] = await Promise.all([
    supabase
      .from("profiles")
      .select("username")
      .eq("user_id", post.user_id)
      .limit(1)
      .returns<Array<{ username: string }>>(),
    getReactionSummaries(supabase, [post.id], currentUserId),
    getPostImagesByPostIds(supabase, [post.id]),
  ]);

  if (imagesResult.error || !imagesResult.data) {
    return { status: "error" };
  }

  return {
    status: "found",
    post: {
      ...post,
      author:
        profileResult.error || !profileResult.data?.[0]
          ? null
          : { username: profileResult.data[0].username },
      images: imagesResult.data?.get(post.id) ?? [],
      reactions: reactionsResult.data?.get(post.id) ?? null,
    },
  };
}

export async function getEditablePost(
  supabase: SupabaseClient,
  postId: string,
  currentUserId: string,
) {
  const result = await supabase
    .from("posts")
    .select(
      "id, title, body, mood, location_name, visibility, post_tags(tags(id, name))",
    )
    .eq("id", postId)
    .eq("user_id", currentUserId)
    .is("deleted_at", null)
    .limit(1)
    .maybeSingle<
      Omit<EditablePost, "tags" | "images"> & RawTagRelations
    >();

  if (result.error || !result.data) {
    return { data: null, error: result.error };
  }

  const post = attachPostTags([result.data])?.[0];

  if (!post) {
    return { data: null, error: TAG_RELATION_LOAD_ERROR };
  }

  const imagesResult = await getPostImagesByPostIds(supabase, [post.id]);

  if (imagesResult.error || !imagesResult.data) {
    return { data: null, error: imagesResult.error };
  }

  return {
    data: {
      ...post,
      images: imagesResult.data.get(post.id) ?? [],
    },
    error: null,
  };
}

export function isPostMood(value: string): value is PostMood {
  return POST_MOODS.some((mood) => mood === value);
}

export function isPostVisibility(value: string): value is PostVisibility {
  return POST_VISIBILITIES.some((visibility) => visibility === value);
}

export function getMoodLabel(mood: PostMood | null) {
  if (!mood) {
    return "気分は未設定";
  }

  return (
    POST_MOOD_OPTIONS.find((option) => option.value === mood)?.label ??
    "気分は未設定"
  );
}

export function getVisibilityLabel(visibility: PostVisibility) {
  return (
    POST_VISIBILITY_OPTIONS.find((option) => option.value === visibility)
      ?.label ?? visibility
  );
}
