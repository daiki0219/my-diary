import type { SupabaseClient } from "@supabase/supabase-js";

export type Profile = {
  user_id: string;
  username: string;
  bio: string | null;
};

export type ProfileCounts = {
  posts: number | null;
  following: number | null;
  followers: number | null;
};

export type ProfileWithCountsResult = {
  profile: Profile | null;
  counts: ProfileCounts;
  profileLoadFailed: boolean;
};

export function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    value,
  );
}

export async function getProfileWithCounts(
  supabase: SupabaseClient,
  userId: string,
): Promise<ProfileWithCountsResult> {
  const [profileResult, postsResult, followingResult, followersResult] =
    await Promise.all([
      supabase
        .from("profiles")
        .select("user_id, username, bio")
        .eq("user_id", userId)
        .maybeSingle(),
      supabase
        .from("posts")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .is("deleted_at", null),
      supabase
        .from("follows")
        .select("follower_id", { count: "exact", head: true })
        .eq("follower_id", userId),
      supabase
        .from("follows")
        .select("following_id", { count: "exact", head: true })
        .eq("following_id", userId),
    ]);

  return {
    profile: profileResult.data,
    counts: {
      posts: postsResult.error ? null : postsResult.count,
      following: followingResult.error ? null : followingResult.count,
      followers: followersResult.error ? null : followersResult.count,
    },
    profileLoadFailed: Boolean(profileResult.error),
  };
}
