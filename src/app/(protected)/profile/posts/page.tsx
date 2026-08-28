import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { PostCard } from "@/components/posts/post-card";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { getOwnPosts } from "@/lib/post-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "自分の日記",
};

type OwnPostsPageProps = {
  searchParams: Promise<{
    status?: string;
  }>;
};

export default async function OwnPostsPage({
  searchParams,
}: OwnPostsPageProps) {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    redirect("/login");
  }

  const [{ data: posts, error: postsError }, params] = await Promise.all([
    getOwnPosts(supabase, userId),
    searchParams,
  ]);

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-2xl">
        <ActionLink className="-ml-3" href="/profile" variant="quiet">
          ← プロフィールへ戻る
        </ActionLink>

        <PageHeader
          className="mt-3"
          description="公開範囲にかかわらず、あなたの未削除の日記を新しい順に表示します。"
          eyebrow="これまでの記録"
          title="自分の日記"
          variant="plain"
        />
        <div className="mt-4">
          <ActionLink href="/posts/new" variant="primary">
            日記を書く
          </ActionLink>
        </div>

        {params.status === "created" && (
          <FeedbackPanel
            aria-live="polite"
            className="mt-5"
            role="status"
            variant="success"
          >
            日記を投稿しました。
          </FeedbackPanel>
        )}

        {postsError ? (
          <FeedbackPanel
            className="mt-5"
            role="alert"
            title="日記を読み込めませんでした"
            variant="error"
          >
            時間をおいて、もう一度お試しください。
          </FeedbackPanel>
        ) : posts && posts.length > 0 ? (
          <div className="mt-5 space-y-4">
            {posts.map((post) => (
              <PostCard canDeletePost key={post.id} post={post} />
            ))}
          </div>
        ) : (
          <EmptyState
            className="mt-5"
            description="最初の日記を、気軽に書いてみましょう。"
            title="まだ日記はありません"
          />
        )}
      </div>
    </section>
  );
}
