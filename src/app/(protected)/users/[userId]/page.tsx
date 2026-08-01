import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { PostCard } from "@/components/posts/post-card";
import { ProfileCard } from "@/components/profile/profile-card";
import { FollowButton } from "@/components/profile/follow-button";
import { getVisiblePostsByUser } from "@/lib/post-data";
import { getProfileWithCounts, isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "ユーザープロフィール",
};

type UserProfilePageProps = {
  params: Promise<{
    userId: string;
  }>;
};

export default async function UserProfilePage({
  params,
}: UserProfilePageProps) {
  const { userId } = await params;
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  if (!isUuid(userId)) {
    notFound();
  }

  if (userId.toLowerCase() === currentUserId.toLowerCase()) {
    redirect("/profile");
  }

  const [result, followResult, accountResult, postsResult] = await Promise.all([
    getProfileWithCounts(supabase, userId),
    supabase
      .from("follows")
      .select("following_id")
      .eq("follower_id", currentUserId)
      .eq("following_id", userId)
      .limit(1)
      .maybeSingle<{ following_id: string }>(),
    supabase
      .from("accounts")
      .select("status")
      .eq("user_id", currentUserId)
      .limit(1)
      .maybeSingle<{ status: string }>(),
    getVisiblePostsByUser(supabase, userId, currentUserId),
  ]);

  if (result.profileLoadFailed) {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          プロフィールの読み込みに失敗しました。時間をおいてもう一度お試しください。
        </p>
      </section>
    );
  }

  if (!result.profile) {
    notFound();
  }

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ← ホームへ戻る
        </Link>

        <div className="mt-5">
          <ProfileCard
            actions={
              <FollowButton
                canManageFollows={accountResult.data?.status === "active"}
                isFollowing={Boolean(followResult.data)}
                targetUserId={userId}
              />
            }
            counts={result.counts}
            isOwnProfile={false}
            profile={result.profile}
          />
        </div>

        <section aria-labelledby="user-posts-heading" className="mt-8">
          <h2
            className="text-2xl font-bold tracking-tight text-stone-800"
            id="user-posts-heading"
          >
            このユーザーの日記
          </h2>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            あなたが閲覧できる日記を新しい順に表示します。
          </p>

          {postsResult.error ? (
            <p
              className="mt-5 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
              role="alert"
            >
              日記を読み込めませんでした。時間をおいてもう一度お試しください。
            </p>
          ) : postsResult.data && postsResult.data.length > 0 ? (
            <>
              <div className="mt-5 space-y-4">
                {postsResult.data.map((post) => (
                  <PostCard
                    canDeletePost={false}
                    key={post.id}
                    post={post}
                  />
                ))}
              </div>
              {postsResult.hasMore && (
                <p className="mt-4 text-center text-sm text-stone-500">
                  最新20件を表示しています。
                </p>
              )}
            </>
          ) : (
            <p className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center text-sm leading-6 text-stone-500 shadow-sm">
              閲覧できる日記はまだありません。
            </p>
          )}
        </section>
      </div>
    </section>
  );
}
