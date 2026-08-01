import type { SupabaseClient } from "@supabase/supabase-js";

import type { Profile } from "@/lib/profile-data";

export const FOLLOW_LIST_DISPLAY_LIMIT = 20;
const FOLLOW_LIST_FETCH_LIMIT = FOLLOW_LIST_DISPLAY_LIMIT + 1;

export type FollowListKind = "following" | "followers";

export type FollowListItem = {
  profile: Profile;
  isFollowing: boolean;
};

export type FollowListResult =
  | {
      status: "success";
      data: FollowListItem[];
      hasMore: boolean;
    }
  | {
      status: "error";
      data: null;
      hasMore: false;
    };

type FollowRow = {
  follower_id: string;
  following_id: string;
  created_at: string;
};

export async function getFollowList(
  supabase: SupabaseClient,
  targetUserId: string,
  currentUserId: string,
  kind: FollowListKind,
): Promise<FollowListResult> {
  const targetColumn = kind === "following" ? "follower_id" : "following_id";
  const listedUserColumn =
    kind === "following" ? "following_id" : "follower_id";

  const followsResult = await supabase
    .from("follows")
    .select("follower_id, following_id, created_at")
    .eq(targetColumn, targetUserId)
    .order("created_at", { ascending: false })
    .order(listedUserColumn, { ascending: false })
    .limit(FOLLOW_LIST_FETCH_LIMIT)
    .returns<FollowRow[]>();

  if (followsResult.error || !followsResult.data) {
    return { status: "error", data: null, hasMore: false };
  }

  const visibleRows = followsResult.data.slice(0, FOLLOW_LIST_DISPLAY_LIMIT);
  const listedUserIds = visibleRows.map((row) => row[listedUserColumn]);

  if (listedUserIds.length === 0) {
    return {
      status: "success",
      data: [],
      hasMore: false,
    };
  }

  const followStateUserIds = listedUserIds.filter(
    (userId) => userId.toLowerCase() !== currentUserId.toLowerCase(),
  );

  const [profilesResult, followStatesResult] = await Promise.all([
    supabase
      .from("profiles")
      .select("user_id, username, bio")
      .in("user_id", listedUserIds)
      .returns<Profile[]>(),
    followStateUserIds.length > 0
      ? supabase
          .from("follows")
          .select("following_id")
          .eq("follower_id", currentUserId)
          .in("following_id", followStateUserIds)
          .returns<Array<{ following_id: string }>>()
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (
    profilesResult.error ||
    !profilesResult.data ||
    followStatesResult.error ||
    !followStatesResult.data
  ) {
    return { status: "error", data: null, hasMore: false };
  }

  const profilesByUserId = new Map(
    profilesResult.data.map((profile) => [profile.user_id, profile]),
  );
  const followingUserIds = new Set(
    followStatesResult.data.map((follow) => follow.following_id),
  );
  const data: FollowListItem[] = [];

  for (const listedUserId of listedUserIds) {
    const profile = profilesByUserId.get(listedUserId);

    if (!profile) {
      return { status: "error", data: null, hasMore: false };
    }

    data.push({
      profile,
      isFollowing: followingUserIds.has(listedUserId),
    });
  }

  return {
    status: "success",
    data,
    hasMore: followsResult.data.length > FOLLOW_LIST_DISPLAY_LIMIT,
  };
}
