import type { SupabaseClient } from "@supabase/supabase-js";

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
};

export async function getOwnPosts(
  supabase: SupabaseClient,
  userId: string,
) {
  return supabase
    .from("posts")
    .select("id, title, body, mood, visibility, created_at")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .returns<Post[]>();
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
