import type { SupabaseClient } from "@supabase/supabase-js";

import type { Profile, ProfileCounts } from "@/lib/profile-data";

export const USER_SEARCH_MAX_LENGTH = 50;
export const USER_SEARCH_RESULT_LIMIT = 20;

export type UserSearchResult = {
  profile: Profile;
  counts: ProfileCounts;
};

export type UserSearchDataResult =
  | {
      status: "success";
      data: UserSearchResult[];
    }
  | {
      status: "error";
      data: null;
    };

type SearchProfileRow = Profile;

function createCountMap(userIds: string[]) {
  return new Map(userIds.map((userId) => [userId, 0]));
}

export async function searchUsers(
  supabase: SupabaseClient,
  query: string,
): Promise<UserSearchDataResult> {
  const searchResult = await supabase
    .rpc("my_diary_search_profiles", { search_query: query })
    .returns<SearchProfileRow[]>();

  if (searchResult.error || !searchResult.data) {
    return { status: "error", data: null };
  }

  const profiles = searchResult.data as unknown as SearchProfileRow[];
  const userIds = profiles.map((profile) => profile.user_id);

  if (userIds.length === 0) {
    return { status: "success", data: [] };
  }

  const [postsResult, followingResult, followersResult] = await Promise.all([
    supabase
      .from("posts")
      .select("user_id")
      .in("user_id", userIds)
      .is("deleted_at", null)
      .returns<Array<{ user_id: string }>>(),
    supabase
      .from("follows")
      .select("follower_id")
      .in("follower_id", userIds)
      .returns<Array<{ follower_id: string }>>(),
    supabase
      .from("follows")
      .select("following_id")
      .in("following_id", userIds)
      .returns<Array<{ following_id: string }>>(),
  ]);

  const posts = createCountMap(userIds);
  const following = createCountMap(userIds);
  const followers = createCountMap(userIds);

  if (!postsResult.error) {
    for (const post of postsResult.data ?? []) {
      posts.set(post.user_id, (posts.get(post.user_id) ?? 0) + 1);
    }
  }

  if (!followingResult.error) {
    for (const follow of followingResult.data ?? []) {
      following.set(
        follow.follower_id,
        (following.get(follow.follower_id) ?? 0) + 1,
      );
    }
  }

  if (!followersResult.error) {
    for (const follow of followersResult.data ?? []) {
      followers.set(
        follow.following_id,
        (followers.get(follow.following_id) ?? 0) + 1,
      );
    }
  }

  return {
    status: "success",
    data: profiles.map((profile) => ({
      profile,
      counts: {
        posts: postsResult.error ? null : (posts.get(profile.user_id) ?? 0),
        following: followingResult.error
          ? null
          : (following.get(profile.user_id) ?? 0),
        followers: followersResult.error
          ? null
          : (followers.get(profile.user_id) ?? 0),
      },
    })),
  };
}
