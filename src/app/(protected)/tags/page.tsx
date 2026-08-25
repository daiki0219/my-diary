import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { DiscoveryTagList } from "@/components/tags/discovery-tag-list";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import {
  decodeTagListCursor,
  getVisibleTags,
} from "@/lib/tag-page-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "タグ一覧",
};

type TagListPageProps = {
  searchParams: Promise<{
    cursor?: string | string[];
  }>;
};

export default async function TagListPage({
  searchParams,
}: TagListPageProps) {
  const supabase = await createClient();
  const [{ data: claimsData, error: claimsError }, query] =
    await Promise.all([supabase.auth.getClaims(), searchParams]);
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const rawCursor = query.cursor;
  const cursor =
    typeof rawCursor === "string" ? decodeTagListCursor(rawCursor) : null;
  const hasInvalidCursor =
    rawCursor !== undefined &&
    (typeof rawCursor !== "string" || cursor === null);

  const result = hasInvalidCursor
    ? null
    : await getVisibleTags(supabase, cursor);

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>

        <PageHeader
          className="mt-3 max-w-xl"
          description="あなたが閲覧できる日記で使われている言葉から、気になる記録を探せます。"
          eyebrow="タグから見つける"
          title="タグ一覧"
          variant="plain"
        />

        {hasInvalidCursor ? (
          <FeedbackPanel
            className="mt-6 max-w-xl"
            role="alert"
            title="ページ情報を確認できませんでした"
            variant="error"
          >
            <p>URLを確認するか、タグ一覧の最初からもう一度お試しください。</p>
            <ActionLink className="mt-4" href="/tags" variant="neutral">
              タグ一覧の最初へ戻る
            </ActionLink>
          </FeedbackPanel>
        ) : result?.error ? (
          <FeedbackPanel
            className="mt-6 max-w-xl"
            role="alert"
            title="タグを読み込めませんでした"
            variant="error"
          >
            時間をおいて、もう一度お試しください。
          </FeedbackPanel>
        ) : result?.data && result.data.length > 0 ? (
          <section aria-labelledby="tag-list-heading" className="mt-6 min-w-0">
            <h2
              className="text-lg font-semibold text-text-primary"
              id="tag-list-heading"
            >
              日記につながるタグ
            </h2>
            <p className="mt-1 text-sm leading-6 text-text-secondary">
              気になる言葉を選んで、そのタグが付いた日記を見てみましょう。
            </p>
            <DiscoveryTagList
              ariaLabel="閲覧できるタグ"
              className="mt-3"
              tags={result.data}
            />

            {result.nextCursor && (
              <Pagination aria-label="タグ一覧のページ移動" className="mt-6">
                <PaginationLink
                  className="w-full"
                  href={`/tags?cursor=${encodeURIComponent(result.nextCursor)}`}
                >
                  <span>次のタグを見る</span>
                  <span aria-hidden="true">→</span>
                </PaginationLink>
              </Pagination>
            )}

            {!result.nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-text-muted">
                閲覧できるタグをすべて表示しました。
              </p>
            )}
          </section>
        ) : cursor ? (
          <EmptyState
            action={
              <ActionLink href="/tags" variant="neutral">
                タグ一覧の最初へ戻る
              </ActionLink>
            }
            className="mt-6 max-w-xl"
            description="閲覧できるタグを最後まで表示しました。"
            title="次のタグはありません"
          />
        ) : (
          <EmptyState
            className="mt-6 max-w-xl"
            description="投稿にタグが付くと、ここから日記を見つけられます。"
            title="閲覧できるタグはまだありません"
          />
        )}
      </div>
    </section>
  );
}
