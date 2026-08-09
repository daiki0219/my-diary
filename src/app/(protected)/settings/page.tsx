import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { TimeZoneForm } from "@/components/settings/timezone-form";
import { getViewerTimeZone } from "@/lib/account-data";
import { createClient } from "@/lib/supabase/server";
import { getTimeZoneOptions } from "@/lib/timezone";

export const metadata: Metadata = {
  title: "設定",
};

export default async function SettingsPage() {
  const supabase = await createClient();
  const timezoneResult = await getViewerTimeZone(supabase);

  if (timezoneResult.error === "unauthenticated") {
    redirect("/login");
  }

  return (
    <section className="flex flex-1 px-4 py-8 sm:px-8 sm:py-10">
      <div className="mx-auto min-w-0 w-full max-w-lg">
        <Link
          className="inline-flex rounded-lg text-sm font-semibold text-stone-600 underline-offset-4 hover:text-stone-900 hover:underline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-orange-600"
          href="/home"
        >
          ← ホームへ戻る
        </Link>

        <div className="mt-5 min-w-0 rounded-3xl bg-orange-50 p-5 sm:p-7">
          <p className="text-sm font-medium text-orange-700">
            あなたの日付表示
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            設定
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            日記を振り返るときに使うタイムゾーンを設定できます。
          </p>
        </div>

        {timezoneResult.error ? (
          <div
            className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5"
            role="alert"
          >
            <h2 className="font-semibold text-stone-800">
              設定を読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : (
          <div className="mt-5 min-w-0 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-7">
            <h2 className="text-xl font-bold text-stone-800">
              タイムゾーン
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-600">
              利用する地域をIANAタイムゾーンから選んでください。
            </p>
            <div className="mt-6">
              <TimeZoneForm
                currentTimeZone={timezoneResult.timezone}
                timeZoneOptions={getTimeZoneOptions(timezoneResult.timezone)}
              />
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
