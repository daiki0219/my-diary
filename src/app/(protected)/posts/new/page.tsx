import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { PostForm } from "@/components/posts/post-form";
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
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/profile/posts"
        >
          ← 自分の日記へ戻る
        </Link>

        <div className="mt-5 rounded-card border border-border-subtle bg-surface-elevated p-5 shadow-surface sm:p-7">
          <p className="text-sm font-medium text-brand-primary-hover">今日の記録</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-text-primary">
            日記を書く
          </h1>
          <p className="mt-3 text-sm leading-6 text-text-secondary">
            今の気持ちや出来事を、あなたのペースで残しましょう。
          </p>

          <div className="mt-7">
            <PostForm />
          </div>
        </div>
      </div>
    </section>
  );
}
