import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { Surface } from "@/components/ui/surface";
import type { UserSearchResult } from "@/lib/user-search-data";

type UserSearchResultsProps = {
  currentUserId: string;
  results: UserSearchResult[];
};

function ResultStat({
  label,
  value,
}: {
  label: string;
  value: number | null;
}) {
  return (
    <div className="flex min-w-0 items-baseline gap-1.5">
      <dt className="text-xs text-text-muted">{label}</dt>
      <dd className="text-sm font-medium tabular-nums text-text-secondary">
        {value ?? "—"}
      </dd>
    </div>
  );
}

export function UserSearchResults({
  currentUserId,
  results,
}: UserSearchResultsProps) {
  if (results.length === 0) {
    return (
      <EmptyState
        description="別のユーザー名でもう一度お試しください。"
        title="該当するユーザーが見つかりませんでした"
      />
    );
  }

  return (
    <section aria-labelledby="search-results-heading">
      <h2
        className="text-lg font-semibold text-text-primary"
        id="search-results-heading"
      >
        検索結果（{results.length}件）
      </h2>
      <Surface
        className="mt-3 overflow-hidden border border-border-subtle/70 px-4 shadow-surface sm:px-5"
        variant="elevated"
      >
        <ul className="divide-y divide-border-subtle/70">
          {results.map(({ profile, counts }) => {
            const username = profile.username.trim() || "ユーザー";
            const initial = Array.from(username)[0] ?? "人";
            const isCurrentUser =
              profile.user_id.toLowerCase() === currentUserId.toLowerCase();
            const href = isCurrentUser
              ? "/profile"
              : `/users/${profile.user_id}`;

            return (
              <li className="min-w-0 py-5" key={profile.user_id}>
                <article className="min-w-0">
                  <div className="flex min-w-0 items-center gap-3">
                    <div
                      aria-hidden="true"
                      className="flex size-12 shrink-0 items-center justify-center rounded-full bg-brand-soft text-lg font-semibold text-brand-primary-hover"
                    >
                      {initial}
                    </div>
                    <div className="min-w-0">
                      <h3 className="break-words text-base font-semibold text-text-primary [overflow-wrap:anywhere] sm:text-lg">
                        {username}
                      </h3>
                      {isCurrentUser && (
                        <p className="mt-0.5 text-xs font-medium text-brand-primary-hover">
                          あなた
                        </p>
                      )}
                    </div>
                  </div>

                  <p className="mt-3 line-clamp-3 whitespace-pre-wrap break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere] sm:pl-15">
                    {profile.bio || "自己紹介はまだありません。"}
                  </p>

                  <dl
                    aria-label={`${username}の件数`}
                    className="mt-3 flex min-w-0 flex-wrap gap-x-5 gap-y-1 sm:pl-15"
                  >
                    <ResultStat label="投稿" value={counts.posts} />
                    <ResultStat label="フォロー" value={counts.following} />
                    <ResultStat label="フォロワー" value={counts.followers} />
                  </dl>

                  <ActionLink
                    className="-ml-3 mt-2 max-w-full justify-start break-words text-left [overflow-wrap:anywhere] sm:ml-12"
                    href={href}
                    variant="quiet"
                  >
                    {isCurrentUser
                      ? "自分のプロフィールを見る"
                      : `${username}のプロフィールを見る`}
                    <span aria-hidden="true">→</span>
                  </ActionLink>
                </article>
              </li>
            );
          })}
        </ul>
      </Surface>
    </section>
  );
}
