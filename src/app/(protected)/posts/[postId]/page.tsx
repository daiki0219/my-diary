import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { CommentList } from "@/components/posts/comment-list";
import { PostDetail } from "@/components/posts/post-detail";
import {
  RelatedPosts,
  type RelatedPostSection,
} from "@/components/posts/related-posts";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { getCommentsForPost } from "@/lib/comment-data";
import { getPostDetail } from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
import {
  getRelatedPostsByAuthor,
  getRelatedPostsByTags,
  type RelatedPostResult,
} from "@/lib/related-post-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "日記の詳細",
};

type PostDetailPageProps = {
  params: Promise<{
    postId: string;
  }>;
  searchParams: Promise<{
    imageCleanup?: string;
    status?: string;
  }>;
};

function resolveRelatedSection(
  result: PromiseSettledResult<RelatedPostResult>,
): RelatedPostSection {
  if (result.status === "rejected" || result.value.data === null) {
    return { posts: [], error: true };
  }

  return { posts: result.value.data, error: false };
}

export default async function PostDetailPage({
  params,
  searchParams,
}: PostDetailPageProps) {
  const { postId } = await params;
  const query = await searchParams;
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  if (!isUuid(postId)) {
    notFound();
  }

  const [result, commentsResult] = await Promise.all([
    getPostDetail(supabase, postId, currentUserId),
    getCommentsForPost(supabase, postId),
  ]);

  if (result.status === "not-found") {
    notFound();
  }

  if (result.status === "error") {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <FeedbackPanel
          className="mx-auto w-full max-w-lg"
          role="alert"
          variant="error"
        >
          日記を読み込めませんでした。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      </section>
    );
  }

  const isOwnPost = result.post.user_id === currentUserId;
  const accountResult = isOwnPost
    ? await supabase
        .from("accounts")
        .select("status")
        .eq("user_id", currentUserId)
        .limit(1)
        .maybeSingle<{ status: string }>()
    : null;
  const canEditPost =
    isOwnPost &&
    !accountResult?.error &&
    accountResult?.data?.status === "active";
  const currentPostTagIds = result.post.tags.map((tag) => tag.id);
  const [authorRelatedResult, tagRelatedResult] = await Promise.allSettled([
    getRelatedPostsByAuthor(supabase, postId, result.post.user_id),
    getRelatedPostsByTags(
      supabase,
      postId,
      result.post.user_id,
      currentPostTagIds,
    ),
  ]);
  const authorRelated = resolveRelatedSection(authorRelatedResult);
  const tagRelated = resolveRelatedSection(tagRelatedResult);
  const hasRelatedPosts =
    authorRelated.posts.length > 0 || tagRelated.posts.length > 0;
  const hasRelatedRegion =
    hasRelatedPosts || authorRelated.error || tagRelated.error;

  return (
    <section className="flex flex-1 px-4 py-6 sm:py-8 lg:py-10">
      <div
        className={
          hasRelatedRegion
            ? "mx-auto w-full min-w-0 max-w-2xl lg:max-w-none"
            : "mx-auto w-full min-w-0 max-w-2xl"
        }
      >
        <div className="w-full max-w-2xl">
          {query.status === "updated" && (
            <FeedbackPanel className="mb-5" role="status" variant="success">
              投稿を更新しました。
            </FeedbackPanel>
          )}
          {query.status === "updated" && query.imageCleanup === "partial" && (
            <FeedbackPanel className="mb-5" role="status" variant="warning">
              投稿内容は保存済みですが、不要になった一部の画像を整理できませんでした。
            </FeedbackPanel>
          )}
          <Link
            className="mb-2 inline-flex min-h-11 items-center rounded-lg px-1 text-sm font-medium text-text-secondary underline-offset-4 transition hover:text-text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            href="/home"
          >
            <span aria-hidden="true">←</span>
            <span className="ml-1">タイムラインへ戻る</span>
          </Link>
        </div>

        <div
          className={
            hasRelatedRegion
              ? "grid min-w-0 lg:grid-cols-[minmax(0,2fr)_minmax(18rem,1fr)] lg:items-start lg:gap-8 xl:gap-10"
              : "min-w-0"
          }
        >
          <div className="w-full min-w-0 max-w-2xl">
            <PostDetail
              canEditPost={canEditPost}
              isOwnPost={isOwnPost}
              post={result.post}
            />
            {hasRelatedPosts && (
              <nav aria-label="関連する日記" className="mt-3 lg:hidden">
                <Link
                  className="inline-flex min-h-11 items-center rounded-lg px-1 text-sm font-medium text-text-secondary underline-offset-4 transition hover:text-text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
                  href="#related-posts"
                >
                  関連する日記を見る
                  <span aria-hidden="true" className="ml-1">
                    ↓
                  </span>
                </Link>
              </nav>
            )}
            <CommentList
              comments={commentsResult.data}
              currentUserId={currentUserId}
              error={Boolean(commentsResult.error)}
              isTruncated={commentsResult.isTruncated}
              postId={postId}
              total={commentsResult.total}
            />
          </div>

          <RelatedPosts author={authorRelated} sameTag={tagRelated} />
        </div>
      </div>
    </section>
  );
}
