import type { Metadata } from "next";

import { FollowListPage } from "@/components/profile/follow-list-page";

export const metadata: Metadata = {
  title: "フォロー中",
};

export default function OwnFollowingPage() {
  return <FollowListPage kind="following" />;
}
