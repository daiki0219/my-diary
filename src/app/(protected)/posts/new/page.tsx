import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { PostForm } from "@/components/posts/post-form";
import { ActionLink } from "@/components/ui/actions";
import { PageHeader } from "@/components/ui/page-header";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "日記を書く",
};

export default async function NewPostPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  if (error || !data?.claims?.sub) {
    redirect("/login");
  }

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-xl">
        <ActionLink
          className="-ml-3"
          href="/profile/posts"
          variant="quiet"
        >
          ← 自分の日記へ戻る
        </ActionLink>

        <PageHeader
          className="mt-3"
          description="今の気持ちや出来事を、あなたのペースで残しましょう。"
          eyebrow="今日の記録"
          title="日記を書く"
          variant="plain"
        />

        <div className="mt-6 sm:mt-8">
          <PostForm />
        </div>
      </div>
    </section>
  );
}
