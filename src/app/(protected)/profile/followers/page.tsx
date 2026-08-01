import type { Metadata } from "next";

import { FollowListPage } from "@/components/profile/follow-list-page";

export const metadata: Metadata = {
  title: "フォロワー",
};

export default function OwnFollowersPage() {
  return <FollowListPage kind="followers" />;
}
