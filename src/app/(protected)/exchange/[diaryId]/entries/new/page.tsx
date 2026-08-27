import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { ExchangeEntryForm } from "@/components/exchange/exchange-entry-form";
import { canonicalizeExchangeUuid } from "@/lib/exchange-cursor";
import { getExchangeDiaryDetail } from "@/lib/exchange-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "交換日記を書く",
};

type NewExchangeEntryPageProps = {
  params: Promise<{
    diaryId: string;
  }>;
};

export default async function NewExchangeEntryPage({
  params,
}: NewExchangeEntryPageProps) {
  const { diaryId } = await params;
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);

  if (!canonicalDiaryId) {
    notFound();
  }

  if (diaryId !== canonicalDiaryId) {
    redirect(`/exchange/${canonicalDiaryId}/entries/new`);
  }

  const diaryResult = await getExchangeDiaryDetail(
    supabase,
    currentUserId,
    canonicalDiaryId,
  );

  if (diaryResult.status === "not-found") {
    notFound();
  }

  if (diaryResult.status === "error") {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          交換日記を読み込めませんでした。時間をおいてもう一度お試しください。
        </p>
      </section>
    );
  }

  if (diaryResult.data.state !== "active") {
    notFound();
  }

  const counterpartName =
    diaryResult.data.counterpart.profile?.username ?? "お相手";
  const diaryTitle =
    diaryResult.data.title ??
    (diaryResult.data.counterpart.profile
      ? `${counterpartName}さんとの交換日記`
      : "交換日記");

  return (
    <section className="flex min-w-0 flex-1 px-4 pb-10 pt-5 sm:px-8 sm:pb-12 sm:pt-7">
      <div className="mx-auto min-w-0 w-full max-w-3xl">
        <Link
          className="inline-flex min-h-11 items-center rounded-control px-2 text-sm font-medium text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          href={`/exchange/${canonicalDiaryId}?view=latest`}
        >
          ← 交換日記へ戻る
        </Link>

        <div className="mt-4 min-w-0 rounded-card bg-surface-muted/65 px-4 py-4 sm:px-5">
          <p className="text-xs font-semibold tracking-[0.12em] text-brand-primary-hover">
            交換日記
          </p>
          <p className="mt-1 min-w-0 break-words font-brand text-xl font-medium leading-8 text-text-primary [overflow-wrap:anywhere]">
            「{diaryTitle}」
          </p>
          <p className="mt-1 min-w-0 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
            {diaryResult.data.counterpart.profile
              ? `${counterpartName}さんと`
              : "お相手と"}
          </p>
        </div>

        <header className="mt-7 min-w-0 px-1 sm:mt-9">
          <p className="text-sm font-medium text-brand-primary-hover">
            新しい日記
          </p>
          <h1 className="mt-2 font-brand text-3xl font-medium tracking-wide text-text-primary sm:text-4xl">
            日記を書く
          </h1>
          <p className="mt-3 text-sm leading-7 text-text-secondary">
            いつでも、書きたい方から。残したいことを、あなたのペースで綴れます。
          </p>
        </header>

        <div className="mt-7 min-w-0 rounded-card bg-surface-elevated px-4 py-6 shadow-surface sm:px-7 sm:py-8">
          <ExchangeEntryForm diaryId={canonicalDiaryId} mode="create" />
        </div>
      </div>
    </section>
  );
}
