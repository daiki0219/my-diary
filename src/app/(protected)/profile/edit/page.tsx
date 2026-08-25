import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { ProfileForm } from "@/components/profile/profile-form";
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
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
      <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6">
        <div className="mx-auto w-full max-w-xl min-w-0">
          <ActionLink className="-ml-3" href="/profile" variant="quiet">
            ← プロフィールへ戻る
          </ActionLink>
          <PageHeader
            className="mt-3"
            title="プロフィールを読み込めませんでした"
            variant="plain"
          />
          <FeedbackPanel className="mt-5" role="alert" variant="error">
            プロフィールの読み込みに失敗しました。時間をおいてもう一度お試しください。
          </FeedbackPanel>
        </div>
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
