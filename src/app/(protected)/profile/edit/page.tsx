import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { ProfileForm } from "@/components/profile/profile-form";
import { ActionLink } from "@/components/ui/actions";
import { PageHeader } from "@/components/ui/page-header";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "プロフィール編集",
};

export default async function EditProfilePage() {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } =
    await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;

  if (claimsError || !userId) {
    redirect("/login");
  }

  const { data: profile, error } = await supabase
    .from("profiles")
    .select("username, bio")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    return (
      <section className="flex flex-1 items-center px-4 py-10 sm:px-8">
        <p
          className="mx-auto w-full max-w-lg rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm leading-6 text-red-700"
          role="alert"
        >
          プロフィールの読み込みに失敗しました。時間をおいてもう一度お試しください。
        </p>
      </section>
    );
  }

  if (!profile) {
    notFound();
  }

  return (
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
      <div className="mx-auto w-full max-w-xl">
        <ActionLink className="-ml-3" href="/profile" variant="quiet">
          ← プロフィールへ戻る
        </ActionLink>

        <PageHeader
          className="mt-3"
          description="サービス内で表示する名前と自己紹介を、あなたの言葉で整えられます。"
          eyebrow="プロフィール設定"
          title="プロフィールを編集"
          variant="plain"
        />

        <div className="mt-6 sm:mt-8">
          <ProfileForm bio={profile.bio} username={profile.username} />
        </div>
      </div>
    </section>
  );
}
