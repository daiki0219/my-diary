import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import { CalendarMonthView } from "@/components/calendar/calendar-month";
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
            あなたのこれまでの記録
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            カレンダー
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            投稿した日とその日の気分から、自分の日記を振り返れます。
          </p>
        </div>

        {result.error || !result.data ? (
          <div
            className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5"
            role="alert"
          >
            <h2 className="font-semibold text-stone-800">
              カレンダーを読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700">
              URLを確認するか、時間をおいてもう一度お試しください。
            </p>
            <Link
              className="mt-5 inline-flex rounded-full border border-red-300 bg-white px-5 py-3 text-sm font-semibold text-red-800 transition hover:bg-red-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
              href="/calendar"
            >
              今月のカレンダーへ戻る
            </Link>
          </div>
        ) : (
          <CalendarMonthView data={result.data} />
        )}
      </div>
    </section>
  );
}
