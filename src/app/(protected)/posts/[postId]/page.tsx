import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { PostDetail } from "@/components/posts/post-detail";
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
};

export default async function PostDetailPage({
  params,
}: PostDetailPageProps) {
  const { postId } = await params;
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

  const result = await getPostDetail(supabase, postId, currentUserId);

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

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <PostDetail
          isOwnPost={result.post.user_id === currentUserId}
          post={result.post}
        />
      </div>
    </section>
  );
}
