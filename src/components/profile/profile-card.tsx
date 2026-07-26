import Link from "next/link";
import type { ReactNode } from "react";

import type { Profile, ProfileCounts } from "@/lib/profile-data";

type ProfileCardProps = {
  profile: Profile;
  counts: ProfileCounts;
  isOwnProfile: boolean;
  actions?: ReactNode;
};

function ProfileStat({
  label,
  value,
}: {
  label: string;
  value: number | null;
}) {
  return (
    <div className="min-w-0 text-center">
      <p className="text-xl font-bold tabular-nums text-stone-800">
        {value ?? "—"}
      </p>
      <p className="mt-1 text-xs text-stone-500">{label}</p>
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
  const hasBio = Boolean(profile.bio);

  return (
    <div className="rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
      <div className="flex min-w-0 items-center gap-4">
        <div
          aria-hidden="true"
          className="flex size-16 shrink-0 items-center justify-center rounded-full bg-orange-100 text-2xl font-bold text-orange-800 sm:size-20 sm:text-3xl"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <p className="text-sm text-stone-500">
            {isOwnProfile ? "あなたのプロフィール" : "プロフィール"}
          </p>
          <h1 className="mt-1 break-words text-2xl font-bold tracking-tight text-stone-800">
            {normalizedUsername || "ユーザー"}
          </h1>
        </div>
      </div>

      <div className="mt-6">
        {hasBio ? (
          <p className="whitespace-pre-wrap break-words text-sm leading-7 text-stone-700">
            {profile.bio}
          </p>
        ) : (
          <p className="text-sm leading-6 text-stone-500">
            {isOwnProfile
              ? "自己紹介はまだありません。プロフィール編集から追加できます。"
              : "自己紹介はまだありません。"}
          </p>
        )}
      </div>

      <div
        aria-label="プロフィールの件数"
        className="mt-6 grid grid-cols-3 gap-2 rounded-2xl bg-stone-50 px-2 py-4"
      >
        <ProfileStat label="投稿" value={counts.posts} />
        <ProfileStat label="フォロー" value={counts.following} />
        <ProfileStat label="フォロワー" value={counts.followers} />
      </div>

      {Object.values(counts).some((count) => count === null) && (
        <p className="mt-3 text-xs leading-5 text-stone-500" role="status">
          一部の件数を取得できませんでした。
        </p>
      )}

      {isOwnProfile && (
        <Link
          className="mt-6 block w-full rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
          href="/profile/edit"
        >
          プロフィールを編集
        </Link>
      )}

      {!isOwnProfile && actions}
    </div>
  );
}
