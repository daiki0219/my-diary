import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { EditPostForm } from "@/components/posts/edit-post-form";
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
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
        <FeedbackPanel
          className="mx-auto w-full max-w-xl"
          role="alert"
          variant="error"
        >
          投稿を読み込めませんでした。時間をおいてもう一度お試しください。
        </FeedbackPanel>
      </section>
    );
  }

  if (!postResult.data) {
    notFound();
  }

  const canEdit =
    !accountResult.error && accountResult.data?.status === "active";

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-xl">
        <ActionLink
          className="-ml-3"
          href={`/posts/${postId}`}
          variant="quiet"
        >
          ← 投稿の詳細へ戻る
        </ActionLink>

        <PageHeader
          className="mt-3"
          description="保存すると、変更した内容と公開範囲がすぐに反映されます。"
          eyebrow="投稿内容の変更"
          title="投稿を編集"
          variant="plain"
        />

        {canEdit ? (
          <div className="mt-6 sm:mt-8">
            <EditPostForm post={postResult.data} />
          </div>
        ) : (
          <FeedbackPanel
            className="mt-6 sm:mt-8"
            role="alert"
            variant="warning"
          >
            現在のアカウント状態では投稿を編集できません。
          </FeedbackPanel>
        )}
      </div>
    </section>
  );
}
