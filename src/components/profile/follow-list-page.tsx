import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { FollowButton } from "@/components/profile/follow-button";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { Surface } from "@/components/ui/surface";
import { getFollowList, type FollowListKind } from "@/lib/follow-data";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

type FollowListPageProps = {
  kind: FollowListKind;
  requestedUserId?: string;
};

export async function FollowListPage({
  kind,
  requestedUserId,
}: FollowListPageProps) {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  if (requestedUserId && !isUuid(requestedUserId)) {
    notFound();
  }

  if (
    requestedUserId &&
    requestedUserId.toLowerCase() === currentUserId.toLowerCase()
  ) {
    redirect(`/profile/${kind}`);
  }

  const targetUserId = requestedUserId ?? currentUserId;
  const isOwnProfile = !requestedUserId;
  const [profileResult, accountResult, listResult] = await Promise.all([
    supabase
      .from("profiles")
      .select("user_id, username, bio")
      .eq("user_id", targetUserId)
      .limit(1)
      .maybeSingle<{ user_id: string; username: string; bio: string | null }>(),
    supabase
      .from("accounts")
      .select("status")
      .eq("user_id", currentUserId)
      .limit(1)
      .maybeSingle<{ status: string }>(),
    getFollowList(supabase, targetUserId, currentUserId, kind),
  ]);

  const backHref = isOwnProfile ? "/profile" : `/users/${targetUserId}`;

  if (profileResult.error) {
    return <ProfileLoadError backHref={backHref} />;
  }

  if (!profileResult.data) {
    notFound();
  }

  const username = profileResult.data.username.trim() || "ユーザー";
  const listLabel = kind === "following" ? "フォロー中" : "フォロワー";
  const title = isOwnProfile ? listLabel : `${username}さんの${listLabel}`;
  const emptyMessage =
    kind === "following"
      ? "表示できるフォロー中ユーザーはいません。"
      : "表示できるフォロワーはいません。";

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-lg min-w-0">
        <ActionLink className="-ml-3" href={backHref} variant="quiet">
          ← プロフィールへ戻る
        </ActionLink>

        <PageHeader
          className="mt-3"
          description="新しくつながったユーザーから順に表示します。"
          eyebrow="ゆるいつながり"
          title={title}
          variant="plain"
        />

        <section aria-label={`${title}の一覧`} className="mt-6 min-w-0">
          {listResult.status === "error" ? (
            <FeedbackPanel role="alert" variant="error">
              一覧を読み込めませんでした。時間をおいてもう一度お試しください。
            </FeedbackPanel>
          ) : listResult.data.length === 0 ? (
            <EmptyState title={emptyMessage} />
          ) : (
            <>
              <Surface
                className="overflow-hidden border border-border-subtle/70 px-4 shadow-surface sm:px-5"
                variant="elevated"
              >
                <ul className="divide-y divide-border-subtle/70">
                  {listResult.data.map(({ profile, isFollowing }) => {
                    const listedUsername =
                      profile.username.trim() || "ユーザー";
                    const initial = Array.from(listedUsername)[0] ?? "人";
                    const isCurrentUser =
                      profile.user_id.toLowerCase() ===
                      currentUserId.toLowerCase();
                    const profileHref = isCurrentUser
                      ? "/profile"
                      : `/users/${profile.user_id}`;

                    return (
                      <li className="min-w-0 py-5" key={profile.user_id}>
                        <div className="min-w-0">
                          <Link
                            className="-ml-2 flex min-h-12 max-w-full min-w-0 items-center justify-start gap-3 rounded-control px-2 py-1.5 text-left transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
                            href={profileHref}
                          >
                            <span
                              aria-hidden="true"
                              className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft text-lg font-semibold text-brand-primary-hover"
                            >
                              {initial}
                            </span>
                            <span className="min-w-0">
                              <span className="block break-words text-base font-semibold text-text-primary [overflow-wrap:anywhere] sm:text-lg">
                                {listedUsername}
                              </span>
                              {isCurrentUser && (
                                <span className="mt-0.5 block text-xs font-medium text-brand-primary-hover">
                                  あなた
                                </span>
                              )}
                            </span>
                          </Link>

                          <p className="mt-2 whitespace-pre-wrap break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere] sm:pl-14">
                            {profile.bio || "自己紹介はまだありません。"}
                          </p>

                          {!isCurrentUser && (
                            <FollowButton
                              canManageFollows={
                                accountResult.data?.status === "active"
                              }
                              className="mt-3 sm:pl-14"
                              compact
                              isFollowing={isFollowing}
                              targetUserId={profile.user_id}
                              targetUsername={listedUsername}
                            />
                          )}
                        </div>
                      </li>
                    );
                  })}
                </ul>
              </Surface>

              {listResult.hasMore && (
                <p className="mt-4 text-center text-sm text-text-muted">
                  最新20件を表示しています。
                </p>
              )}
            </>
          )}
        </section>
      </div>
    </section>
  );
}

function ProfileLoadError({ backHref }: { backHref: string }) {
  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-lg">
        <ActionLink className="-ml-3" href={backHref} variant="quiet">
          ← プロフィールへ戻る
        </ActionLink>
        <PageHeader
          className="mt-3"
          title="プロフィールを表示できません"
          variant="plain"
        />
        <FeedbackPanel className="mt-5" role="alert" variant="error">
          プロフィールの読み込みに失敗しました。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      </div>
    </section>
  );
}
