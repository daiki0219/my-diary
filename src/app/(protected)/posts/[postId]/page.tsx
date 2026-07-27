import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { CommentForm } from "@/components/posts/comment-form";
import { CommentList } from "@/components/posts/comment-list";
import { PostDetail } from "@/components/posts/post-detail";
import { getCommentsForPost } from "@/lib/comment-data";
import { getPostDetail } from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "日記の詳細",
};

type PostDetailPageProps = {
  params: Promise<{
    postId: string;
  }>;
  searchParams: Promise<{
    status?: string;
  }>;
};

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
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          日記を読み込めませんでした。時間をおいてもう一度お試しください。
        </p>
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

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        {query.status === "updated" && (
          <p
            className="mb-5 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm leading-6 text-emerald-800"
            role="status"
          >
            投稿を更新しました。
          </p>
        )}
        <PostDetail
          canEditPost={canEditPost}
          isOwnPost={isOwnPost}
          post={result.post}
        />
        <CommentList
          comments={commentsResult.data}
          currentUserId={currentUserId}
          error={Boolean(commentsResult.error)}
          isTruncated={commentsResult.isTruncated}
          postId={postId}
          total={commentsResult.total}
        />
        <CommentForm postId={postId} />
      </div>
    </section>
  );
}
