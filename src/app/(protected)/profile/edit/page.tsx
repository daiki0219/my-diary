import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";

import { ProfileForm } from "@/components/profile/profile-form";
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
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto w-full max-w-lg">
        <div className="rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
          <p className="text-sm font-medium text-orange-700">プロフィール設定</p>
          <h1 className="mt-2 text-2xl font-bold tracking-tight text-stone-800">
            プロフィールを編集
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            サービス内で表示する名前と自己紹介を設定できます。
          </p>

          <div className="mt-7">
            <ProfileForm bio={profile.bio} username={profile.username} />
          </div>
        </div>
      </div>
    </section>
  );
}
