import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { TimelinePostCard } from "@/components/posts/timeline-post-card";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import { isUuid } from "@/lib/profile-data";
import {
  decodeTagPostCursor,
  getVisiblePostsForTag,
  getVisibleTag,
} from "@/lib/tag-page-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "タグの日記",
};

type TagDetailPageProps = {
  params: Promise<{
    tagId: string;
  }>;
  searchParams: Promise<{
    cursor?: string | string[];
  }>;
};

export default async function TagDetailPage({
  params,
  searchParams,
}: TagDetailPageProps) {
  const [{ tagId }, query] = await Promise.all([params, searchParams]);
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  if (!isUuid(tagId)) {
    notFound();
  }

  const rawCursor = query.cursor;
  const cursor =
    typeof rawCursor === "string" ? decodeTagPostCursor(rawCursor) : null;

  if (
    rawCursor !== undefined &&
    (typeof rawCursor !== "string" || cursor === null)
  ) {
    notFound();
  }

  const canonicalTagId = tagId.toLowerCase();

  if (tagId !== canonicalTagId) {
    const canonicalQuery = rawCursor
      ? `?${new URLSearchParams({ cursor: rawCursor }).toString()}`
      : "";
    redirect(`/tags/${canonicalTagId}${canonicalQuery}`);
  }

  const tagResult = await getVisibleTag(supabase, canonicalTagId);

  if (tagResult.error) {
    return (
      <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
        <div className="mx-auto w-full max-w-2xl min-w-0">
          <ActionLink className="-ml-3" href="/tags" variant="quiet">
            ← タグ一覧へ戻る
          </ActionLink>
          <PageHeader
            className="mt-3 max-w-xl"
            title="タグを表示できません"
            variant="plain"
          />
          <FeedbackPanel
            className="mt-5 max-w-xl"
            role="alert"
            variant="error"
          >
            タグを読み込めませんでした。時間をおいてもう一度お試しください。
          </FeedbackPanel>
        </div>
      </section>
    );
  }

  if (!tagResult.data) {
    notFound();
  }

  const postsResult = await getVisiblePostsForTag(
    supabase,
    canonicalTagId,
    currentUserId,
    cursor,
  );

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl min-w-0">
        <ActionLink className="-ml-3" href="/tags" variant="quiet">
          ← タグ一覧へ戻る
        </ActionLink>

        <PageHeader
          className="mt-3 max-w-xl"
          description="あなたが閲覧できる日記だけを、新しい順に表示します。"
          eyebrow="タグが付いた日記"
          title={`#${tagResult.data.name}`}
          variant="plain"
        />

        {postsResult.error ? (
          <FeedbackPanel
            className="mt-6 max-w-xl"
            role="alert"
            title="日記を読み込めませんでした"
            variant="error"
          >
            時間をおいて、もう一度お試しください。
          </FeedbackPanel>
        ) : postsResult.data && postsResult.data.length > 0 ? (
          <>
            <ul
              aria-label={`${tagResult.data.name}の付いた日記`}
              className="mt-6 space-y-4"
            >
              {postsResult.data.map((post) => (
                <li className="min-w-0" key={post.id}>
                  <TimelinePostCard post={post} />
                </li>
              ))}
            </ul>

            {postsResult.nextCursor && (
              <Pagination
                aria-label="タグの日記一覧のページ移動"
                className="mt-6"
              >
                <PaginationLink
                  className="w-full"
                  href={`/tags/${canonicalTagId}?cursor=${encodeURIComponent(postsResult.nextCursor)}`}
                >
                  <span>次の投稿を見る</span>
                  <span aria-hidden="true">→</span>
                </PaginationLink>
              </Pagination>
            )}

            {!postsResult.nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-text-muted">
                閲覧できる日記をすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <EmptyState
            action={
              <ActionLink href={`/tags/${canonicalTagId}`} variant="neutral">
                最初の投稿へ戻る
              </ActionLink>
            }
            className="mt-6 max-w-xl"
            description="閲覧できる日記を最後まで表示しました。"
            title="次の投稿はありません"
          />
        ) : (
          <EmptyState
            action={
              <ActionLink href="/tags" variant="quiet">
                別のタグを見る
              </ActionLink>
            }
            className="mt-6 max-w-xl"
            description="公開範囲が変わった可能性があります。タグ一覧から別のタグも見てみましょう。"
            title="閲覧できる日記はありません"
          />
        )}
      </div>
    </section>
  );
}
