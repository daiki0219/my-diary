import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { CalendarMonthView } from "@/components/calendar/calendar-month";
import { ActionLink } from "@/components/ui/actions";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { getCalendarMonthData } from "@/lib/calendar-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "カレンダー",
};

type CalendarPageProps = {
  searchParams: Promise<{
    month?: string | string[];
    date?: string | string[];
  }>;
};

export default async function CalendarPage({ searchParams }: CalendarPageProps) {
  const supabase = await createClient();
  const [{ data: claimsData, error: claimsError }, query] = await Promise.all([
    supabase.auth.getClaims(),
    searchParams,
  ]);

  if (claimsError || !claimsData?.claims?.sub) {
    redirect("/login");
  }

  const result = await getCalendarMonthData(supabase, {
    month: query.month,
    date: query.date,
  });

  return (
    <section className="flex flex-1 px-4 pb-10 pt-6 sm:px-8 sm:pb-12 sm:pt-8">
      <div className="mx-auto w-full min-w-0 max-w-5xl">
        <ActionLink
          className="-ml-3"
          href="/home"
          variant="quiet"
        >
          ← ホームへ戻る
        </ActionLink>

        <PageHeader
          className="mt-4 max-w-2xl"
          description="投稿した日とその日の気分から、自分の日記を振り返れます。"
          eyebrow="あなたのこれまでの記録"
          title="カレンダー"
          variant="plain"
        />

        {result.error || !result.data ? (
          <FeedbackPanel
            className="mt-6 max-w-2xl"
            role="alert"
            title="カレンダーを読み込めませんでした"
            variant="error"
          >
            <p>
              URLを確認するか、時間をおいてもう一度お試しください。
            </p>
            <ActionLink
              className="mt-4"
              href="/calendar"
              variant="neutral"
            >
              今月のカレンダーへ戻る
            </ActionLink>
          </FeedbackPanel>
        ) : (
          <CalendarMonthView data={result.data} />
        )}
      </div>
    </section>
  );
}
