import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { ProfileCard } from "@/components/profile/profile-card";
import { getProfileWithCounts } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "プロフィール",
};

type ProfilePageProps = {
  searchParams: Promise<{
    status?: string;
  }>;
};

export default async function ProfilePage({
  searchParams,
}: ProfilePageProps) {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    redirect("/login");
  }

  const result = await getProfileWithCounts(supabase, userId);

  if (result.profileLoadFailed) {
    return (
      <ProfileLoadError message="プロフィールの読み込みに失敗しました。時間をおいてもう一度お試しください。" />
    );
  }

  if (!result.profile) {
    notFound();
  }

  const params = await searchParams;
  const shouldSuggestEditing = result.profile.username === "新しいユーザー";

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ← ホームへ戻る
        </Link>

        {params.status === "updated" && (
          <p
            aria-live="polite"
            className="mt-5 rounded-2xl border border-green-200 bg-green-50 px-4 py-3 text-sm text-green-800"
            role="status"
          >
            プロフィールを更新しました。
          </p>
        )}

        {shouldSuggestEditing && (
          <p className="mt-5 rounded-2xl bg-orange-50 px-4 py-3 text-sm leading-6 text-orange-800">
            ユーザー名や自己紹介を設定すると、あなたらしいプロフィールになります。
          </p>
        )}

        <div className="mt-5 grid gap-3 sm:grid-cols-2">
          <Link
            className="rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/posts/new"
          >
            日記を書く
          </Link>
          <Link
            className="rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/profile/posts"
          >
            自分の日記
          </Link>
        </div>

        <Link
          className="mt-3 block w-full rounded-full border border-stone-300 bg-white px-5 py-3 text-center font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
          href="/search"
        >
          ユーザーを探す
        </Link>

        <div className="mt-5">
          <ProfileCard
            counts={result.counts}
            isOwnProfile
            profile={result.profile}
          />
        </div>
      </div>
    </section>
  );
}

function ProfileLoadError({ message }: { message: string }) {
  return (
    <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
      <div className="mx-auto w-full max-w-lg rounded-3xl border border-red-200 bg-red-50 p-6">
        <h1 className="text-xl font-bold text-stone-800">
          プロフィールを表示できません
        </h1>
        <p className="mt-3 text-sm leading-6 text-red-700" role="alert">
          {message}
        </p>
        <Link
          className="mt-5 inline-flex rounded-lg font-semibold text-stone-700 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ホームへ戻る
        </Link>
      </div>
    </section>
  );
}
