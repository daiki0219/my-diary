import Link from "next/link";

import { Surface } from "@/components/ui/surface";
import type { ProfileCounts } from "@/lib/profile-data";

type HomeProfileSummaryProps = {
  profile: {
    username: string;
    bio: string | null;
  };
  counts: ProfileCounts;
};

type HomeProfileStatProps = {
  href: string;
  label: string;
  value: number | null;
  getAccessibleLabel: (value: number | null) => string;
};

function HomeProfileStat({
  href,
  label,
  value,
  getAccessibleLabel,
}: HomeProfileStatProps) {
  return (
    <Link
      aria-label={getAccessibleLabel(value)}
      className="flex min-h-12 min-w-0 flex-col items-center justify-center rounded-lg px-1 py-1.5 text-center transition hover:bg-surface-elevated focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
      href={href}
    >
      <span className="text-xs font-semibold tabular-nums text-text-primary xl:text-sm">
        {value ?? "—"}
      </span>
      <span className="mt-0.5 whitespace-nowrap text-[10px] leading-4 text-text-muted xl:text-xs">
        {label}
      </span>
    </Link>
  );
}

export function HomeProfileSummary({
  profile,
  counts,
}: HomeProfileSummaryProps) {
  const username = profile.username.trim() || "ユーザー";
  const initial = Array.from(username)[0] ?? "人";
  const bio = profile.bio?.trim();

  return (
    <Surface
      aria-labelledby="home-profile-heading"
      as="section"
      className="p-5 xl:p-6"
    >
      <div className="flex items-center justify-between gap-3">
        <h2
          className="text-lg font-semibold text-text-primary"
          id="home-profile-heading"
        >
          プロフィール
        </h2>
        <Link
          className="inline-flex min-h-10 items-center rounded-lg px-2 text-sm font-medium text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          href="/profile/edit"
        >
          編集
        </Link>
      </div>

      <div className="mt-3 flex min-w-0 items-center gap-3 xl:gap-4">
        <div
          aria-hidden="true"
          className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft text-lg font-semibold text-brand-primary-hover xl:size-16 xl:text-2xl"
        >
          {initial}
        </div>
        <div className="min-w-0">
          <Link
            aria-label={`${username}のプロフィールを見る`}
            className="inline-flex min-h-10 max-w-full items-center rounded-lg px-1 font-semibold text-text-primary transition hover:bg-surface-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            href="/profile"
          >
            <span className="break-words [overflow-wrap:anywhere]">
              {username}
            </span>
          </Link>
        </div>
      </div>

      {bio && (
        <p className="mt-3 line-clamp-2 whitespace-pre-wrap break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere] xl:line-clamp-3">
          {bio}
        </p>
      )}

      <div
        aria-label="プロフィールの件数"
        className="mt-4 grid min-w-0 grid-cols-3 gap-1 rounded-control bg-surface-muted/60 p-1"
        role="group"
      >
        <HomeProfileStat
          getAccessibleLabel={(value) =>
            value === null
              ? "投稿件数を取得できません。投稿一覧を見る"
              : `投稿 ${value}件を見る`
          }
          href="/profile/posts"
          label="投稿"
          value={counts.posts}
        />
        <HomeProfileStat
          getAccessibleLabel={(value) =>
            value === null
              ? "フォロー中の人数を取得できません。フォロー中一覧を見る"
              : `${value}人をフォロー中。フォロー中一覧を見る`
          }
          href="/profile/following"
          label="フォロー中"
          value={counts.following}
        />
        <HomeProfileStat
          getAccessibleLabel={(value) =>
            value === null
              ? "フォロワー数を取得できません。フォロワー一覧を見る"
              : `フォロワー ${value}人を見る`
          }
          href="/profile/followers"
          label="フォロワー"
          value={counts.followers}
        />
      </div>
    </Surface>
  );
}
