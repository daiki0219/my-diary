import type { Metadata } from "next";

import { FollowListPage } from "@/components/profile/follow-list-page";

export const metadata: Metadata = {
  title: "フォロー中",
};

type UserFollowingPageProps = {
  params: Promise<{
    userId: string;
  }>;
};

export default async function UserFollowingPage({
  params,
}: UserFollowingPageProps) {
  const { userId } = await params;

  return <FollowListPage kind="following" requestedUserId={userId} />;
}
