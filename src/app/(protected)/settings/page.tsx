import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { TimeZoneForm } from "@/components/settings/timezone-form";
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { Surface } from "@/components/ui/surface";
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
        <ActionLink href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>

        <PageHeader
          className="mt-5"
          description="日記を振り返るときに使うタイムゾーンを設定できます。"
          eyebrow="あなたの日付表示"
          title="設定"
        />

        {timezoneResult.error ? (
          <FeedbackPanel
            className="mt-5"
            role="alert"
            title="設定を読み込めませんでした"
            variant="error"
          >
            時間をおいて、もう一度お試しください。
          </FeedbackPanel>
        ) : (
          <Surface className="mt-5 min-w-0 p-5 sm:p-7" variant="elevated">
            <h2 className="text-xl font-semibold text-text-primary">
              タイムゾーン
            </h2>
            <p className="mt-2 text-sm leading-6 text-text-secondary">
              利用する地域をIANAタイムゾーンから選んでください。
            </p>
            <div className="mt-6">
              <TimeZoneForm
                currentTimeZone={timezoneResult.timezone}
                timeZoneOptions={getTimeZoneOptions(timezoneResult.timezone)}
              />
            </div>
          </Surface>
        )}
      </div>
    </section>
  );
}
