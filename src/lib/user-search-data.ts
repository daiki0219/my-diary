import type { SupabaseClient } from "@supabase/supabase-js";

import {
  isUuid,
  type Profile,
  type ProfileCounts,
} from "@/lib/profile-data";

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

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function isSearchProfileRow(value: unknown): value is SearchProfileRow {
  return (
    typeof value === "object" &&
    value !== null &&
    hasExactKeys(value, ["user_id", "username", "bio"]) &&
    "user_id" in value &&
    "username" in value &&
    "bio" in value &&
    typeof value.user_id === "string" &&
    isUuid(value.user_id) &&
    typeof value.username === "string" &&
    (value.bio === null || typeof value.bio === "string")
  );
}

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

  const profiles = searchResult.data as unknown[];

  if (
    profiles.length > USER_SEARCH_RESULT_LIMIT ||
    !profiles.every(isSearchProfileRow)
  ) {
    return { status: "error", data: null };
  }

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
