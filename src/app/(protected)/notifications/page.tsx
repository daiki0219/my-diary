import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import {
  MarkAllNotificationsReadAction,
  NotificationOpenAction,
  NotificationReadAction,
} from "@/components/notifications/notification-actions";
import {
  decodeNotificationCursor,
  getNotifications,
  getUnreadNotificationCount,
  type NotificationListItem,
} from "@/lib/notification-data";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "通知",
};

type NotificationsPageProps = {
  searchParams: Promise<{
    cursor?: string | string[];
  }>;
};

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  dateStyle: "medium",
  timeStyle: "short",
  timeZone: "Asia/Tokyo",
});

function getNotificationMessage(notification: NotificationListItem) {
  if (!notification.actorUsername) {
    return "この通知の送信者を現在表示できません";
  }

  const username = notification.actorUsername;

  switch (notification.notificationType) {
    case "follow":
      return `${username}さんにフォローされました`;
    case "reaction":
      return `${username}さんがあなたの投稿にリアクションしました`;
    case "comment":
      return `${username}さんがあなたの投稿にコメントしました`;
    case "reply":
      return `${username}さんがあなたのコメントに返信しました`;
  }
}

export default async function NotificationsPage({
  searchParams,
}: NotificationsPageProps) {
  const supabase = await createClient();
  const [{ data: claimsData, error: claimsError }, query] =
    await Promise.all([supabase.auth.getClaims(), searchParams]);
  const currentUserId = claimsData?.claims?.sub;

  if (claimsError || !currentUserId) {
    redirect("/login");
  }

  const rawCursor = query.cursor;
  const cursor =
    typeof rawCursor === "string"
      ? decodeNotificationCursor(rawCursor)
      : null;
  const hasInvalidCursor =
    rawCursor !== undefined &&
    (typeof rawCursor !== "string" || cursor === null);
  const [notificationsResult, unreadResult] = hasInvalidCursor
    ? [null, null]
    : await Promise.all([
        getNotifications(supabase, cursor),
        getUnreadNotificationCount(supabase),
      ]);
  const hasLoadError = Boolean(
    notificationsResult?.error || unreadResult?.error,
  );
  const unreadCount = unreadResult?.count ?? 0;

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
            あなたへのお知らせ
          </p>
          <h1 className="mt-2 text-3xl font-bold tracking-tight text-stone-800">
            通知
          </h1>
          <p className="mt-3 text-sm leading-6 text-stone-600">
            フォロー、リアクション、コメント、返信を新しい順に確認できます。
          </p>
          {!hasInvalidCursor && !hasLoadError && (
            <div className="mt-5 flex min-w-0 flex-col gap-3 rounded-2xl border border-orange-100 bg-white/80 p-4 sm:flex-row sm:items-center sm:justify-between">
              <p
                aria-live="polite"
                className="min-w-0 break-words text-sm font-semibold text-stone-700 [overflow-wrap:anywhere]"
              >
                未読 {unreadCount.toLocaleString("ja-JP")}件
              </p>
              {unreadCount > 0 && <MarkAllNotificationsReadAction />}
            </div>
          )}
        </div>

        {hasInvalidCursor ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              ページ情報を確認できませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              URLを確認するか、通知一覧の最初からもう一度お試しください。
            </p>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-red-300 bg-white px-5 py-2 text-sm font-semibold text-red-800 underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-red-700"
              href="/notifications"
            >
              通知一覧の最初へ戻る
            </Link>
          </div>
        ) : hasLoadError ? (
          <div className="mt-5 rounded-3xl border border-red-200 bg-red-50 p-5">
            <h2 className="font-semibold text-stone-800">
              通知を読み込めませんでした
            </h2>
            <p className="mt-2 text-sm leading-6 text-red-700" role="alert">
              時間をおいて、もう一度お試しください。
            </p>
          </div>
        ) : notificationsResult?.data &&
          notificationsResult.data.length > 0 ? (
          <>
            <ul aria-label="通知一覧" className="mt-5 min-w-0 space-y-3">
              {notificationsResult.data.map((notification) => {
                const message = getNotificationMessage(notification);

                return (
                  <li className="min-w-0" key={notification.id}>
                    <article
                      aria-label={`${message}、${notification.isRead ? "既読" : "未読"}`}
                      className={`min-w-0 rounded-3xl border p-5 shadow-sm sm:p-6 ${
                        notification.isRead
                          ? "border-stone-200 bg-white"
                          : "border-orange-200 bg-orange-50"
                      }`}
                    >
                      <div className="flex min-w-0 flex-wrap items-center gap-2">
                        <span
                          className={`rounded-full px-3 py-1 text-xs font-bold ${
                            notification.isRead
                              ? "bg-stone-100 text-stone-600"
                              : "bg-orange-600 text-white"
                          }`}
                        >
                          {notification.isRead ? "既読" : "未読"}
                        </span>
                        <time
                          className="text-xs text-stone-500"
                          dateTime={notification.createdAt}
                        >
                          {dateFormatter.format(
                            new Date(notification.createdAt),
                          )}
                        </time>
                      </div>
                      <p className="mt-3 min-w-0 break-words text-[15px] font-semibold leading-7 text-stone-800 [overflow-wrap:anywhere]">
                        {message}
                      </p>

                      {!notification.targetAvailable && (
                        <p className="mt-2 text-sm leading-6 text-stone-600">
                          この通知の対象は現在表示できません。
                        </p>
                      )}

                      <div className="mt-4 flex min-w-0 flex-col items-start gap-3 sm:flex-row sm:flex-wrap">
                        {notification.targetAvailable && (
                          <NotificationOpenAction
                            notificationId={notification.id}
                          />
                        )}
                        {!notification.isRead && (
                          <NotificationReadAction
                            notificationId={notification.id}
                          />
                        )}
                      </div>
                    </article>
                  </li>
                );
              })}
            </ul>

            {notificationsResult.nextCursor && (
              <nav aria-label="通知一覧のページ移動" className="mt-6">
                <Link
                  className="flex min-h-11 w-full items-center justify-center rounded-full border border-orange-300 bg-orange-50 px-5 py-3 text-center font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
                  href={`/notifications?cursor=${encodeURIComponent(notificationsResult.nextCursor)}`}
                >
                  次の通知を見る →
                </Link>
              </nav>
            )}

            {!notificationsResult.nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-stone-500">
                現在表示できる通知をすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              次の通知はありません
            </h2>
            <Link
              className="mt-5 inline-flex min-h-10 items-center rounded-full border border-orange-300 bg-orange-50 px-5 py-2 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
              href="/notifications"
            >
              通知一覧の最初へ戻る
            </Link>
          </div>
        ) : (
          <div className="mt-5 rounded-3xl border border-stone-200 bg-white p-6 text-center shadow-sm">
            <h2 className="text-lg font-bold text-stone-800">
              まだ通知はありません
            </h2>
            <p className="mt-2 text-sm leading-6 text-stone-500">
              フォローやリアクション、コメントがあるとここに表示されます。
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
