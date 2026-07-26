import type { SupabaseClient } from "@supabase/supabase-js";

import { getCommentCounts } from "@/lib/comment-data";
import {
  getReactionSummaries,
  type ReactionSummary,
} from "@/lib/reaction-data";

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
  visibility: PostVisibility;
  created_at: string;
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

export async function getOwnPosts(
  supabase: SupabaseClient,
  userId: string,
) {
  const postsResult = await supabase
    .from("posts")
    .select("id, title, body, mood, visibility, created_at")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .returns<Array<Omit<Post, "reactions" | "commentCount">>>();

  if (postsResult.error || !postsResult.data) {
    return {
      data: null,
      error: postsResult.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  const postIds = postsResult.data.map((post) => post.id);
  const [reactionsResult, commentsResult] = await Promise.all([
    getReactionSummaries(supabase, postIds, userId),
    getCommentCounts(supabase, postIds),
  ]);

  return {
    data: postsResult.data.map((post) => ({
      ...post,
      reactions: reactionsResult.data?.get(post.id) ?? null,
      commentCount: commentsResult.data?.get(post.id) ?? null,
    })),
    error: null,
    reactionsError: reactionsResult.error,
    commentsError: commentsResult.error,
  };
}

export async function getTimelinePosts(
  supabase: SupabaseClient,
  currentUserId: string,
) {
  const postsResult = await supabase
    .from("posts")
    .select("id, user_id, title, body, mood, visibility, created_at")
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(50)
    .returns<
      Array<Omit<TimelinePost, "author" | "reactions" | "commentCount">>
    >();

  if (postsResult.error || !postsResult.data) {
    return {
      data: null,
      error: postsResult.error,
      reactionsError: null,
      commentsError: null,
    };
  }

  const authorIds = [...new Set(postsResult.data.map((post) => post.user_id))];
  const postIds = postsResult.data.map((post) => post.id);
  const [profilesResult, reactionsResult, commentsResult] = await Promise.all([
    authorIds.length > 0
      ? supabase
          .from("profiles")
          .select("user_id, username")
          .in("user_id", authorIds)
          .returns<Array<{ user_id: string; username: string }>>()
      : Promise.resolve({ data: [], error: null }),
    getReactionSummaries(
      supabase,
      postIds,
      currentUserId,
    ),
    getCommentCounts(supabase, postIds),
  ]);
  const profilesByUserId = new Map(
    (profilesResult.data ?? []).map((profile) => [
      profile.user_id,
      { username: profile.username },
    ]),
  );

  return {
    data: postsResult.data.map((post) => ({
      ...post,
      author: profilesByUserId.get(post.user_id) ?? null,
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
    .select("id, user_id, title, body, mood, visibility, created_at")
    .eq("id", postId)
    .is("deleted_at", null)
    .limit(1)
    .returns<Array<Omit<PostDetail, "author" | "reactions">>>();

  if (postsResult.error || !postsResult.data) {
    return { status: "error" };
  }

  const post = postsResult.data[0];

  if (!post) {
    return { status: "not-found" };
  }

  const [profileResult, reactionsResult] = await Promise.all([
    supabase
      .from("profiles")
      .select("username")
      .eq("user_id", post.user_id)
      .limit(1)
      .returns<Array<{ username: string }>>(),
    getReactionSummaries(supabase, [post.id], currentUserId),
  ]);

  return {
    status: "found",
    post: {
      ...post,
      author:
        profileResult.error || !profileResult.data?.[0]
          ? null
          : { username: profileResult.data[0].username },
      reactions: reactionsResult.data?.get(post.id) ?? null,
    },
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
