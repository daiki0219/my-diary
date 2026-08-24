import Link from "next/link";
import type { ReactNode } from "react";

import { ActionLink } from "@/components/ui/actions";
import { Surface } from "@/components/ui/surface";
import type { Profile, ProfileCounts } from "@/lib/profile-data";

type ProfileCardProps = {
  profile: Profile;
  counts: ProfileCounts;
  isOwnProfile: boolean;
  actions?: ReactNode;
};

function ProfileStat({
  href,
  label,
  value,
}: {
  href?: string;
  label: string;
  value: number | null;
}) {
  const content = (
    <>
      <span className="text-sm font-semibold tabular-nums text-text-primary">
        {value ?? "—"}
      </span>
      <span className="mt-0.5 text-xs text-text-muted">{label}</span>
    </>
  );

  return href ? (
    <Link
      aria-label={`${label}一覧を見る`}
      className="flex min-h-12 min-w-0 flex-col items-center justify-center rounded-control px-1 py-1.5 text-center transition hover:bg-surface-elevated focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
      href={href}
    >
      {content}
    </Link>
  ) : (
    <div className="flex min-h-12 min-w-0 flex-col items-center justify-center px-1 py-1.5 text-center">
      {content}
    </div>
  );
}

export function ProfileCard({
  profile,
  counts,
  isOwnProfile,
  actions,
}: ProfileCardProps) {
  const normalizedUsername = profile.username.trim();
  const initial = Array.from(normalizedUsername)[0] ?? "人";
  const hasBio = Boolean(profile.bio?.trim());

  return (
    <Surface className="p-5 shadow-surface sm:p-7" variant="elevated">
      <div className="flex min-w-0 items-start gap-4 sm:gap-5">
        <div
          aria-hidden="true"
          className="flex size-16 shrink-0 items-center justify-center rounded-full bg-brand-soft text-2xl font-semibold text-brand-primary-hover sm:size-20 sm:text-3xl"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <p className="text-xs font-medium text-text-muted sm:text-sm">
            {isOwnProfile ? "あなたのプロフィール" : "プロフィール"}
          </p>
          <h1 className="mt-1 break-words text-2xl font-semibold tracking-tight text-text-primary [overflow-wrap:anywhere] sm:text-3xl">
            {normalizedUsername || "ユーザー"}
          </h1>
        </div>
      </div>

      <div className="mt-5 sm:mt-6">
        {hasBio ? (
          <p className="whitespace-pre-wrap break-words text-sm leading-7 text-text-secondary [overflow-wrap:anywhere] sm:text-base">
            {profile.bio}
          </p>
        ) : (
          <p className="text-sm leading-6 text-text-muted">
            {isOwnProfile
              ? "自己紹介はまだありません。プロフィール編集から追加できます。"
              : "自己紹介はまだありません。"}
          </p>
        )}
      </div>

      <div
        aria-label="プロフィールの件数"
        className="mt-5 grid min-w-0 grid-cols-3 gap-1 rounded-control bg-surface-muted/60 p-1 sm:mt-6"
        role="group"
      >
        <ProfileStat label="投稿" value={counts.posts} />
        <ProfileStat
          href={
            isOwnProfile
              ? "/profile/following"
              : `/users/${profile.user_id}/following`
          }
          label="フォロー"
          value={counts.following}
        />
        <ProfileStat
          href={
            isOwnProfile
              ? "/profile/followers"
              : `/users/${profile.user_id}/followers`
          }
          label="フォロワー"
          value={counts.followers}
        />
      </div>

      {Object.values(counts).some((count) => count === null) && (
        <p className="mt-3 text-xs leading-5 text-text-muted" role="status">
          一部の件数を取得できませんでした。
        </p>
      )}

      {isOwnProfile && (
        <ActionLink
          className="mt-5 w-full sm:w-auto"
          href="/profile/edit"
          variant="neutral"
        >
          プロフィールを編集
        </ActionLink>
      )}

      {!isOwnProfile && actions}
    </Surface>
  );
}
