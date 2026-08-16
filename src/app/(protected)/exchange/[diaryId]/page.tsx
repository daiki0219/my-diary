import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { ArchiveExchangeDiaryButton } from "@/components/exchange/archive-exchange-diary-button";
import {
  DeletedExchangeEntryStatus,
  DeleteExchangeEntryButton,
} from "@/components/exchange/delete-exchange-entry-button";
import { ExchangeDiaryTitleForm } from "@/components/exchange/exchange-diary-title-form";
import {
  ReportExchangeEntryButton,
  ReportExchangeUserButton,
} from "@/components/exchange/report-exchange-entry-button";
import { PostImageGallery } from "@/components/posts/post-image-gallery";
import {
  getExchangeDiaryDetail,
  getExchangeEntryPage,
  getLatestExchangeEntry,
  type ExchangeActiveEntry,
  type ExchangeDiaryDetail,
  type ExchangeEntry,
  type LatestExchangeEntry,
} from "@/lib/exchange-data";
import { canonicalizeExchangeUuid } from "@/lib/exchange-cursor";
import {
  buildExchangeEntryQuery,
  parseExchangeEntryQuery,
  type ExchangeSearchParams,
} from "@/lib/exchange-query";
import { getMoodLabel } from "@/lib/post-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "交換日記の詳細",
};

type ExchangeDiaryPageProps = {
  params: Promise<{
    diaryId: string;
  }>;
  searchParams: Promise<ExchangeSearchParams>;
};

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

function getCounterpartName(diary: ExchangeDiaryDetail) {
  return diary.counterpart.profile?.username ?? "利用できないユーザー";
}

function getDiaryTitle(diary: ExchangeDiaryDetail) {
  if (diary.title) {
    return diary.title;
  }

  return diary.counterpart.profile
    ? `${diary.counterpart.profile.username}さんとの交換日記`
    : "交換日記";
}

function getAuthorName(diary: ExchangeDiaryDetail, participantId: string) {
  const participant = diary.participants.find(
    (candidate) => candidate.participantId === participantId,
  );

  if (!participant) {
    return null;
  }

  if (participant.participantId === diary.viewerParticipant.participantId) {
    return "あなた";
  }

  return participant.profile?.username ?? "利用できないユーザー";
}

function getNextTurnMessage(
  diary: ExchangeDiaryDetail,
  latestEntry: LatestExchangeEntry | null,
) {
  if (!latestEntry) {
    return "最初の日記を書いてみましょう";
  }

  const nextParticipant = diary.participants.find(
    (participant) =>
      participant.participantId !== latestEntry.authorParticipantId,
  );
  const latestAuthor = diary.participants.find(
    (participant) =>
      participant.participantId === latestEntry.authorParticipantId,
  );

  if (!latestAuthor || !nextParticipant) {
    return null;
  }

  if (
    nextParticipant.participantId === diary.viewerParticipant.participantId
  ) {
    return "次はあなたの番";
  }

  return nextParticipant.profile
    ? `次は${nextParticipant.profile.username}さんの番`
    : "次は相手の方の番";
}

function buildEntryHref(
  diaryId: string,
  mode: "oldest" | "latest",
  cursor?: string,
) {
  const query = buildExchangeEntryQuery(mode, cursor);
  return query ? `/exchange/${diaryId}?${query}` : `/exchange/${diaryId}`;
}

function EntryTags({ tags }: { tags: ExchangeActiveEntry["tags"] }) {
  if (tags.length === 0) {
    return null;
  }

  return (
    <ul aria-label="タグ" className="mt-4 flex min-w-0 max-w-full flex-wrap gap-2">
      {tags.map((tag) => (
        <li className="min-w-0 max-w-full" key={tag.tagId}>
          <span className="inline-flex min-h-8 max-w-full items-center break-words rounded-full border border-orange-200 bg-orange-50 px-3 py-1 text-xs font-semibold text-orange-900 [overflow-wrap:anywhere]">
            #{tag.name}
          </span>
        </li>
      ))}
    </ul>
  );
}

function ActiveEntryArticle({
  diary,
  entry,
  position,
}: {
  diary: ExchangeDiaryDetail;
  entry: ExchangeActiveEntry;
  position: number;
}) {
  const authorName = getAuthorName(diary, entry.authorParticipantId);
  const isOwnEntry =
    entry.authorParticipantId ===
      diary.viewerParticipant.participantId;
  const canEdit = diary.state === "active" && isOwnEntry;

  if (!authorName) {
    return null;
  }

  return (
    <article
      aria-label={`このページの${position}件目、${authorName}の日記`}
      className="min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
    >
      <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <p className="min-w-0 break-words font-semibold text-stone-800 [overflow-wrap:anywhere]">
          {authorName}
        </p>
        <div className="flex shrink-0 flex-col items-start gap-2 sm:items-end">
          <time className="text-xs text-stone-500" dateTime={entry.createdAt}>
            {dateFormatter.format(new Date(entry.createdAt))}
          </time>
          {canEdit && (
            <Link
              aria-label={`このページの${position}件目、${dateFormatter.format(new Date(entry.createdAt))}の日記を編集`}
              className="inline-flex min-h-9 items-center rounded-full border border-stone-300 bg-white px-3 py-1 text-xs font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href={`/exchange/${diary.diaryId}/entries/${entry.entryId}/edit`}
            >
              編集
            </Link>
          )}
        </div>
      </div>

      {entry.title && (
        <h3 className="mt-5 break-words text-xl font-bold leading-8 text-stone-800 [overflow-wrap:anywhere]">
          {entry.title}
        </h3>
      )}

      <div className="mt-4 flex flex-wrap gap-2 text-xs">
        {entry.mood && (
          <span className="rounded-full bg-orange-50 px-3 py-1 font-medium text-orange-800">
            気分：{getMoodLabel(entry.mood)}
          </span>
        )}
        {entry.images.length > 0 && (
          <span className="rounded-full bg-stone-100 px-3 py-1 font-medium text-stone-700">
            画像 {entry.images.length}枚
          </span>
        )}
      </div>

      {entry.locationName && (
        <p className="mt-3 min-w-0 break-words text-sm leading-6 text-stone-500 [overflow-wrap:anywhere]">
          <span className="font-medium text-stone-600">場所:</span>{" "}
          {entry.locationName}
        </p>
      )}

      <EntryTags tags={entry.tags} />

      <p className="mt-6 whitespace-pre-wrap break-words text-[15px] leading-7 text-stone-700 [overflow-wrap:anywhere]">
        {entry.body}
      </p>

      <PostImageGallery images={entry.images} variant="exchange-entry" />

      <div className="mt-5 border-t border-stone-100 pt-4">
        {isOwnEntry ? (
          <DeleteExchangeEntryButton
            accessibleName={`このページの${position}件目、${dateFormatter.format(new Date(entry.createdAt))}の日記を削除`}
            diaryId={diary.diaryId}
            entryId={entry.entryId}
          />
        ) : (
          <div aria-label="安全に関する操作" className="min-w-0 space-y-3" role="group">
            <p className="text-xs font-semibold text-stone-500">
              安全に関する操作
            </p>
            <div className="flex min-w-0 flex-col items-start gap-3">
              <ReportExchangeEntryButton
                accessibleName={`このページの${position}件目、${authorName}の${dateFormatter.format(new Date(entry.createdAt))}の日記そのものを通報`}
                diaryId={diary.diaryId}
                entryId={entry.entryId}
              />
              {diary.counterpart.profile && (
                <ReportExchangeUserButton
                  accessibleName={`このページの${position}件目、${diary.counterpart.profile.username}さんを、この日記を関連情報として添付可能な状態で通報`}
                  counterpartName={diary.counterpart.profile.username}
                  diaryId={diary.diaryId}
                  relatedEntryId={entry.entryId}
                />
              )}
            </div>
          </div>
        )}
      </div>
    </article>
  );
}

function DeletedEntryArticle({
  diary,
  entry,
  position,
}: {
  diary: ExchangeDiaryDetail;
  entry: Extract<ExchangeEntry, { kind: "deleted" }>;
  position: number;
}) {
  const authorName = getAuthorName(diary, entry.authorParticipantId);

  if (!authorName) {
    return null;
  }

  return (
    <article
      aria-label={`このページの${position}件目、${authorName}の削除された日記`}
      className="min-w-0 rounded-3xl border border-stone-200 bg-stone-50 p-5 shadow-sm sm:p-6"
    >
      <div className="flex min-w-0 flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
        <p className="min-w-0 break-words font-semibold text-stone-700 [overflow-wrap:anywhere]">
          {authorName}
        </p>
        <time
          className="shrink-0 text-xs text-stone-500"
          dateTime={entry.createdAt}
        >
          {dateFormatter.format(new Date(entry.createdAt))}
        </time>
      </div>
      <DeletedExchangeEntryStatus />
    </article>
  );
}

export default async function ExchangeDiaryPage({
  params,
  searchParams,
}: ExchangeDiaryPageProps) {
  const [{ diaryId }, rawQuery] = await Promise.all([params, searchParams]);
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

  const query = parseExchangeEntryQuery(rawQuery, canonicalDiaryId);

  if (!query) {
    notFound();
  }

  if (diaryId !== canonicalDiaryId) {
    const rawCursor =
      typeof rawQuery.cursor === "string" ? rawQuery.cursor : undefined;
    redirect(buildEntryHref(canonicalDiaryId, query.mode, rawCursor));
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
        <div className="mx-auto w-full max-w-lg">
          <h1 className="text-2xl font-bold text-stone-800">交換日記</h1>
          <p
            className="mt-4 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
            role="alert"
          >
          交換日記を読み込めませんでした。時間をおいてもう一度お試しください。
          </p>
        </div>
      </section>
    );
  }

  const diary = diaryResult.data;
  const [entriesResult, latestEntryResult] = await Promise.all([
    getExchangeEntryPage(
      supabase,
      canonicalDiaryId,
      query.mode,
      query.cursor,
    ),
    getLatestExchangeEntry(supabase, canonicalDiaryId),
  ]);
  const nextTurnMessage = latestEntryResult.error
    ? null
    : getNextTurnMessage(diary, latestEntryResult.data);
  const hasUnknownAuthor = Boolean(
    entriesResult.data?.some(
      (entry) => getAuthorName(diary, entry.authorParticipantId) === null,
    ),
  );
  const hasEntryLoadError = Boolean(
    entriesResult.error ||
      latestEntryResult.error ||
      nextTurnMessage === null ||
      hasUnknownAuthor,
  );
  const title = getDiaryTitle(diary);
  const counterpartName = getCounterpartName(diary);

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href={`/exchange?view=${diary.state}`}
        >
          ← 交換日記一覧へ戻る
        </Link>

        <header className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="min-w-0">
              <p className="text-sm font-medium text-orange-700">ふたりの記録</p>
              <h1 className="mt-2 break-words text-3xl font-bold tracking-tight text-stone-800 [overflow-wrap:anywhere]">
                {title}
              </h1>
            </div>
            <span
              className={`w-fit shrink-0 rounded-full px-3 py-1 text-xs font-bold ${
                diary.state === "active"
                  ? "bg-orange-700 text-white"
                  : "bg-stone-200 text-stone-700"
              }`}
            >
              {diary.state === "active" ? "交換中" : "終了済み"}
            </span>
          </div>

          <p className="mt-4 min-w-0 break-words text-sm leading-6 text-stone-700 [overflow-wrap:anywhere]">
            参加者：あなた と {counterpartName}
          </p>
          <p className="mt-2 text-sm leading-6 text-stone-600">
            開始：
            <time dateTime={diary.startedAt}>
              {dateFormatter.format(new Date(diary.startedAt))}
            </time>
          </p>

          {diary.state === "archived" && diary.archivedAt && (
            <div className="mt-3 rounded-2xl border border-stone-200 bg-white/80 p-4">
              <p className="text-sm leading-6 text-stone-700">
                この交換日記は終了しています
              </p>
              <p className="mt-1 text-xs text-stone-500">
                終了：
                <time dateTime={diary.archivedAt}>
                  {dateFormatter.format(new Date(diary.archivedAt))}
                </time>
              </p>
            </div>
          )}

          {diary.counterpart.profile && (
            <div className="mt-5 min-w-0 rounded-2xl border border-stone-200 bg-white/80 p-4">
              <p className="text-xs font-semibold text-stone-500">
                安全に関する操作
              </p>
              <p className="mt-1 min-w-0 break-words text-sm leading-6 text-stone-700 [overflow-wrap:anywhere]">
                相手ユーザーについて運営へ報告できます。日記の終了とは別の操作です。
              </p>
              <div className="mt-3">
                <ReportExchangeUserButton
                  accessibleName={`${diary.counterpart.profile.username}さんを通報`}
                  counterpartName={diary.counterpart.profile.username}
                  diaryId={canonicalDiaryId}
                />
              </div>
            </div>
          )}

          {diary.state === "active" && (
            <ExchangeDiaryTitleForm
              diaryId={canonicalDiaryId}
              initialTitle={diary.title}
            />
          )}

          {!hasEntryLoadError && nextTurnMessage && (
            <p className="mt-5 rounded-2xl border border-orange-200 bg-white px-4 py-3 text-sm font-bold leading-6 text-orange-900">
              {nextTurnMessage}
            </p>
          )}

          {diary.state === "active" && (
            <>
              <Link
                className="mt-5 inline-flex min-h-11 w-full items-center justify-center rounded-full bg-orange-600 px-5 py-3 text-center font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 sm:w-auto"
                href={`/exchange/${canonicalDiaryId}/entries/new`}
              >
                新しい日記を書く
              </Link>
              <ArchiveExchangeDiaryButton diaryId={canonicalDiaryId} />
            </>
          )}
        </header>

        <section aria-labelledby="exchange-entries-heading" className="mt-8">
          <div className="flex min-w-0 flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div className="min-w-0">
              <h2
                className="text-2xl font-bold tracking-tight text-stone-800"
                id="exchange-entries-heading"
              >
                日記の記録
              </h2>
              <p className="mt-2 text-sm leading-6 text-stone-600">
                {query.mode === "latest"
                  ? "最近の日記を、古いものから順に表示しています。"
                  : "最初の日記から、古いものを順に表示しています。"}
              </p>
            </div>
            <nav aria-label="日記の表示位置" className="shrink-0">
              {query.mode === "latest" ? (
                <Link
                  className="inline-flex min-h-10 items-center rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-700 transition hover:bg-stone-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-600"
                  href={buildEntryHref(canonicalDiaryId, "oldest")}
                >
                  最初から読む
                </Link>
              ) : (
                <Link
                  className="inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-4 py-2 text-sm font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  href={buildEntryHref(canonicalDiaryId, "latest")}
                >
                  最新の日記へ
                </Link>
              )}
            </nav>
          </div>

          {hasEntryLoadError ? (
            <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
              <h3 className="font-semibold text-stone-800">
                日記の記録を読み込めませんでした
              </h3>
              <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
                時間をおいて、もう一度お試しください。
              </p>
            </div>
          ) : entriesResult.data && entriesResult.data.length > 0 ? (
            <ul aria-label="交換日記の記録" className="mt-5 min-w-0 space-y-4">
              {entriesResult.data.map((entry, index) => (
                <li className="min-w-0" key={entry.entryId}>
                  {entry.kind === "deleted" ? (
                    <DeletedEntryArticle
                      diary={diary}
                      entry={entry}
                      position={index + 1}
                    />
                  ) : (
                    <ActiveEntryArticle
                      diary={diary}
                      entry={entry}
                      position={index + 1}
                    />
                  )}
                </li>
              ))}
            </ul>
          ) : query.cursor ? (
            <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
              <h3 className="text-lg font-bold text-stone-800">
                このページに表示できる日記はありません
              </h3>
              <Link
                className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                href={buildEntryHref(canonicalDiaryId, query.mode)}
              >
                {query.mode === "latest" ? "最近の日記へ戻る" : "最初の日記へ戻る"}
              </Link>
            </div>
          ) : (
            <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
              <h3 className="text-lg font-bold text-stone-800">
                まだ日記はありません
              </h3>
              <p className="mt-2 text-sm leading-6 text-stone-500">
                最初の日記を書いてみましょう。
              </p>
            </div>
          )}

          {!hasEntryLoadError && entriesResult.nextCursor && (
            <nav aria-label="交換日記の記録のページ移動" className="mt-6">
              <Link
                className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                href={buildEntryHref(
                  canonicalDiaryId,
                  query.mode,
                  entriesResult.nextCursor,
                )}
              >
                {query.mode === "latest" ? "さらに前の20件" : "次の20件"} →
              </Link>
            </nav>
          )}

          {!hasEntryLoadError &&
            query.cursor &&
            !entriesResult.nextCursor && (
              <p className="mt-6 text-center text-sm text-stone-500">
                この方向で表示できる日記をすべて表示しました。
              </p>
            )}
        </section>
      </div>
    </section>
  );
}
