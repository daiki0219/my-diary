import type { Metadata } from "next";

import { FollowListPage } from "@/components/profile/follow-list-page";

export const metadata: Metadata = {
  title: "フォロワー",
};

type UserFollowersPageProps = {
  params: Promise<{
    userId: string;
  }>;
};

export default async function UserFollowersPage({
  params,
}: UserFollowersPageProps) {
  const { userId } = await params;

  return <FollowListPage kind="followers" requestedUserId={userId} />;
}
