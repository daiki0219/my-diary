import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { ExchangeEntryForm } from "@/components/exchange/exchange-entry-form";
import { canonicalizeExchangeUuid } from "@/lib/exchange-cursor";
import {
  getEditableExchangeEntry,
  getExchangeDiaryDetail,
} from "@/lib/exchange-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "交換日記を編集",
};

type EditExchangeEntryPageProps = {
  params: Promise<{
    diaryId: string;
    entryId: string;
  }>;
};

export default async function EditExchangeEntryPage({
  params,
}: EditExchangeEntryPageProps) {
  const { diaryId, entryId } = await params;
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);
  const canonicalEntryId = canonicalizeExchangeUuid(entryId);

  if (!canonicalDiaryId || !canonicalEntryId) {
    notFound();
  }

  if (diaryId !== canonicalDiaryId || entryId !== canonicalEntryId) {
    redirect(
      `/exchange/${canonicalDiaryId}/entries/${canonicalEntryId}/edit`,
    );
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

  const entryResult = await getEditableExchangeEntry(
    supabase,
    canonicalDiaryId,
    canonicalEntryId,
    diaryResult.data.viewerParticipant.participantId,
  );

  if (entryResult.status === "not-found") {
    notFound();
  }

  if (entryResult.status === "error") {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          日記を読み込めませんでした。時間をおいてもう一度お試しください。
        </p>
      </section>
    );
  }

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href={`/exchange/${canonicalDiaryId}?view=latest`}
        >
          ← 交換日記へ戻る
        </Link>

        <div className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
          <p className="text-sm font-medium text-orange-700">投稿内容の変更</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            交換日記を編集
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            保存すると、タイトル・本文・気分・場所・タグの変更が反映されます。
          </p>

          <div className="mt-7">
            <ExchangeEntryForm
              diaryId={canonicalDiaryId}
              entry={entryResult.data}
              mode="edit"
            />
          </div>
        </div>
      </div>
    </section>
  );
}
