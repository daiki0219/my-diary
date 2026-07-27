import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { EditPostForm } from "@/components/posts/edit-post-form";
import { getEditablePost } from "@/lib/post-data";
import { isUuid } from "@/lib/profile-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "投稿を編集",
};

type EditPostPageProps = {
  params: Promise<{
    postId: string;
  }>;
};

export default async function EditPostPage({ params }: EditPostPageProps) {
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

  const [postResult, accountResult] = await Promise.all([
    getEditablePost(supabase, postId, currentUserId),
    supabase
      .from("accounts")
      .select("status")
      .eq("user_id", currentUserId)
      .limit(1)
      .maybeSingle<{ status: string }>(),
  ]);

  if (postResult.error) {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          投稿を読み込めませんでした。時間をおいてもう一度お試しください。
        </p>
      </section>
    );
  }

  if (!postResult.data) {
    notFound();
  }

  const canEdit =
    !accountResult.error && accountResult.data?.status === "active";

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href={`/posts/${postId}`}
        >
          ← 投稿の詳細へ戻る
        </Link>

        <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
          <p className="text-sm font-medium text-orange-700">投稿内容の変更</p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            投稿を編集
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            保存すると、変更した内容と公開範囲がすぐに反映されます。
          </p>

          {canEdit ? (
            <div className="mt-7">
              <EditPostForm post={postResult.data} />
            </div>
          ) : (
            <p
              className="mt-7 rounded-2xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm leading-6 text-amber-800"
              role="alert"
            >
              現在のアカウント状態では投稿を編集できません。
            </p>
          )}
        </div>
      </div>
    </section>
  );
}
