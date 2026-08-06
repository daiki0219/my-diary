import Link from "next/link";

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
    <div className="min-w-0 text-center">
      <p className="font-bold tabular-nums text-stone-800">{value ?? "—"}</p>
      <p className="mt-1 text-xs text-stone-500">{label}</p>
    </div>
  );
}

export function UserSearchResults({
  currentUserId,
  results,
}: UserSearchResultsProps) {
  if (results.length === 0) {
    return (
      <div className="rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
        <h2 className="text-lg font-bold text-stone-800">
          該当するユーザーが見つかりませんでした
        </h2>
        <p className="mt-2 text-sm leading-6 text-stone-500">
          別のユーザー名でもう一度お試しください。
        </p>
      </div>
    );
  }

  return (
    <section aria-labelledby="search-results-heading">
      <h2
        className="text-lg font-bold text-stone-800"
        id="search-results-heading"
      >
        検索結果（{results.length}件）
      </h2>
      <ul className="mt-3 space-y-4">
        {results.map(({ profile, counts }) => {
          const username = profile.username.trim() || "ユーザー";
          const initial = Array.from(username)[0] ?? "人";
          const isCurrentUser =
            profile.user_id.toLowerCase() === currentUserId.toLowerCase();
          const href = isCurrentUser
            ? "/profile"
            : `/users/${profile.user_id}`;

          return (
            <li className="min-w-0" key={profile.user_id}>
              <article className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm">
                <div className="flex min-w-0 items-center gap-3">
                  <div
                    aria-hidden="true"
                    className="flex size-12 shrink-0 items-center justify-center rounded-full bg-orange-100 text-lg font-bold text-orange-800"
                  >
                    {initial}
                  </div>
                  <div className="min-w-0">
                    <h3 className="break-words text-lg font-bold text-stone-800">
                      {username}
                    </h3>
                    {isCurrentUser && (
                      <p className="mt-0.5 text-xs font-semibold text-orange-700">
                        あなた
                      </p>
                    )}
                  </div>
                </div>

                <p className="mt-4 line-clamp-3 whitespace-pre-wrap break-words text-sm leading-6 text-stone-600">
                  {profile.bio || "自己紹介はまだありません。"}
                </p>

                <div
                  aria-label={`${username}の件数`}
                  className="mt-4 grid grid-cols-3 gap-2 rounded-2xl bg-stone-50 px-2 py-3"
                >
                  <ResultStat label="投稿" value={counts.posts} />
                  <ResultStat label="フォロー" value={counts.following} />
                  <ResultStat label="フォロワー" value={counts.followers} />
                </div>

                <Link
                  className="mt-4 block w-full break-words rounded-full border border-orange-300 bg-orange-50 px-4 py-2.5 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  href={href}
                >
                  {isCurrentUser
                    ? "自分のプロフィールを見る"
                    : `${username}のプロフィールを見る`}
                </Link>
              </article>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
