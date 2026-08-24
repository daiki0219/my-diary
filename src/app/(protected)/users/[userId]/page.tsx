import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { ExchangeProfileActions } from "@/components/exchange/exchange-profile-actions";
import { PostCard } from "@/components/posts/post-card";
import { ProfileCard } from "@/components/profile/profile-card";
import { FollowButton } from "@/components/profile/follow-button";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { getExchangeProfileContext } from "@/lib/exchange-data";
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

  const [
    result,
    followResult,
    accountResult,
    postsResult,
    exchangeContextResult,
  ] = await Promise.all([
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
    getExchangeProfileContext(supabase, currentUserId, userId),
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
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl">
        <ActionLink
          className="-ml-3"
          href="/home"
          variant="quiet"
        >
          ← ホームへ戻る
        </ActionLink>

        <div className="mt-4 sm:mt-5">
          <ProfileCard
            actions={
              <FollowButton
                canManageFollows={accountResult.data?.status === "active"}
                className="mt-5 sm:max-w-xs"
                isFollowing={Boolean(followResult.data)}
                targetUserId={userId}
                targetUsername={result.profile.username.trim() || "ユーザー"}
              />
            }
            counts={result.counts}
            isOwnProfile={false}
            profile={result.profile}
          />
        </div>

        <div className="mt-6">
          <ExchangeProfileActions
            canManageExchange={Boolean(
              accountResult.data?.status === "active" &&
                exchangeContextResult.data &&
                !exchangeContextResult.error,
            )}
            isBlockingInvitations={
              exchangeContextResult.data?.isBlockingInvitations ?? false
            }
            isMutualFollowing={
              exchangeContextResult.data?.isMutualFollowing ?? false
            }
            pendingDirection={
              exchangeContextResult.data?.pendingDirection ?? null
            }
            targetUserId={userId}
            targetUsername={result.profile.username}
          />
        </div>

        <section aria-labelledby="user-posts-heading" className="mt-10">
          <h2
            className="font-brand text-2xl font-medium tracking-wide text-text-primary"
            id="user-posts-heading"
          >
            このユーザーの日記
          </h2>
          <p className="mt-2 text-sm leading-6 text-text-muted">
            あなたが閲覧できる日記を新しい順に表示します。
          </p>

          {postsResult.error ? (
            <FeedbackPanel className="mt-5" role="alert" variant="error">
              日記を読み込めませんでした。時間をおいてもう一度お試しください。
            </FeedbackPanel>
          ) : postsResult.data && postsResult.data.length > 0 ? (
            <>
              <div className="mt-5 space-y-4">
                {postsResult.data.map((post) => (
                  <PostCard
                    canDeletePost={false}
                    headingAs="h3"
                    key={post.id}
                    post={post}
                  />
                ))}
              </div>
              {postsResult.hasMore && (
                <p className="mt-4 text-center text-sm text-text-muted">
                  最新20件を表示しています。
                </p>
              )}
            </>
          ) : (
            <EmptyState
              className="mt-5"
              title="閲覧できる日記はまだありません。"
              titleAs="h3"
            />
          )}
        </section>
      </div>
    </section>
  );
}
