import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { FollowButton } from "@/components/profile/follow-button";
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
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg min-w-0">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href={backHref}
        >
          ← プロフィールへ戻る
        </Link>

        <div className="mt-5 min-w-0">
          <p className="text-sm font-medium text-orange-700">ゆるいつながり</p>
          <h1 className="mt-2 break-words text-3xl font-bold tracking-tight text-stone-800 [overflow-wrap:anywhere]">
            {title}
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            新しくつながったユーザーから順に表示します。
          </p>
        </div>

        <section aria-label={`${title}の一覧`} className="mt-6 min-w-0">
          {listResult.status === "error" ? (
            <p
              className="rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700 [overflow-wrap:anywhere]"
              role="alert"
            >
              一覧を読み込めませんでした。時間をおいてもう一度お試しください。
            </p>
          ) : listResult.data.length === 0 ? (
            <p className="rounded-3xl border border-stone-200 bg-white p-6 text-center text-sm leading-6 text-stone-500 shadow-sm [overflow-wrap:anywhere]">
              {emptyMessage}
            </p>
          ) : (
            <>
              <div className="space-y-4">
                {listResult.data.map(({ profile, isFollowing }) => {
                  const listedUsername = profile.username.trim() || "ユーザー";
                  const initial = Array.from(listedUsername)[0] ?? "人";
                  const isCurrentUser =
                    profile.user_id.toLowerCase() ===
                    currentUserId.toLowerCase();
                  const profileHref = isCurrentUser
                    ? "/profile"
                    : `/users/${profile.user_id}`;

                  return (
                    <article
                      className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm"
                      key={profile.user_id}
                    >
                      <Link
                        className="flex min-w-0 items-center gap-3 rounded-xl focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
                        href={profileHref}
                      >
                        <span
                          aria-hidden="true"
                          className="flex size-12 shrink-0 items-center justify-center rounded-full bg-orange-100 text-lg font-bold text-orange-800"
                        >
                          {initial}
                        </span>
                        <span className="min-w-0">
                          <span className="block break-words text-lg font-bold text-stone-800 [overflow-wrap:anywhere]">
                            {listedUsername}
                          </span>
                          {isCurrentUser && (
                            <span className="mt-0.5 block text-xs font-semibold text-orange-700">
                              あなた
                            </span>
                          )}
                        </span>
                      </Link>

                      <p className="mt-4 whitespace-pre-wrap break-words text-sm leading-6 text-stone-600 [overflow-wrap:anywhere]">
                        {profile.bio || "自己紹介はまだありません。"}
                      </p>

                      {!isCurrentUser && (
                        <FollowButton
                          canManageFollows={
                            accountResult.data?.status === "active"
                          }
                          className="mt-4"
                          isFollowing={isFollowing}
                          targetUserId={profile.user_id}
                        />
                      )}
                    </article>
                  );
                })}
              </div>

              {listResult.hasMore && (
                <p className="mt-4 text-center text-sm text-stone-500">
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
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
      <div className="mx-auto w-full max-w-lg rounded-3xl border border-red-200 bg-red-50 p-6">
        <h1 className="text-xl font-bold text-stone-800">
          プロフィールを表示できません
        </h1>
        <p className="mt-3 text-sm leading-6 text-red-700" role="alert">
          プロフィールの読み込みに失敗しました。時間をおいてもう一度お試しください。
        </p>
        <Link
          className="mt-5 inline-flex rounded-lg font-semibold text-stone-700 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href={backHref}
        >
          プロフィールへ戻る
        </Link>
      </div>
    </section>
  );
}
