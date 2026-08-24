import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { ProfileCard } from "@/components/profile/profile-card";
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { Surface } from "@/components/ui/surface";
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
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl">
        <ActionLink
          className="-ml-3"
          href="/home"
          variant="quiet"
        >
          ← ホームへ戻る
        </ActionLink>

        {params.status === "updated" && (
          <FeedbackPanel
            aria-live="polite"
            className="mt-4"
            role="status"
            variant="success"
          >
            プロフィールを更新しました。
          </FeedbackPanel>
        )}

        {shouldSuggestEditing && (
          <p className="mt-4 rounded-control bg-brand-soft/70 px-4 py-3 text-sm leading-6 text-brand-primary-hover">
            ユーザー名や自己紹介を設定すると、あなたらしいプロフィールになります。
          </p>
        )}

        <div className="mt-4 sm:mt-5">
          <ProfileCard
            counts={result.counts}
            isOwnProfile
            profile={result.profile}
          />
        </div>

        <Surface
          aria-labelledby="profile-diary-heading"
          as="section"
          className="mt-6 p-5 sm:p-6"
          variant="muted"
        >
          <h2
            className="font-brand text-xl font-medium tracking-wide text-text-primary"
            id="profile-diary-heading"
          >
            日記
          </h2>
          <p className="mt-1 text-sm leading-6 text-text-muted">
            これまでの日記を読んだり、今日のことを残したりできます。
          </p>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <ActionLink href="/profile/posts" variant="neutral">
              自分の日記
            </ActionLink>
            <ActionLink href="/posts/new" variant="secondary">
              日記を書く
            </ActionLink>
          </div>
        </Surface>

        <nav
          aria-label="プロフィールから移動"
          className="mt-6 border-t border-border-subtle pt-5"
        >
          <p className="text-sm font-medium text-text-muted">つながり</p>
          <div className="mt-2 grid min-w-0 gap-1 sm:grid-cols-2">
            <ActionLink
              className="w-full min-w-0 justify-between"
              href="/exchange"
              variant="quiet"
            >
              <span>交換日記</span>
              <span aria-hidden="true">→</span>
            </ActionLink>
            <ActionLink
              className="w-full min-w-0 justify-between"
              href="/search"
              variant="quiet"
            >
              <span>ユーザーを探す</span>
              <span aria-hidden="true">→</span>
            </ActionLink>
          </div>
        </nav>
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
