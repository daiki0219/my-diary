import type { Metadata } from "next";
import { redirect } from "next/navigation";

import {
  MarkAllNotificationsReadAction,
  NotificationOpenAction,
  NotificationReadAction,
} from "@/components/notifications/notification-actions";
import { ActionLink } from "@/components/ui/actions";
import { EmptyState } from "@/components/ui/empty-state";
import { FeedbackPanel } from "@/components/ui/feedback-panel";
import { PageHeader } from "@/components/ui/page-header";
import { Pagination, PaginationLink } from "@/components/ui/pagination";
import { Surface } from "@/components/ui/surface";
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
  if (notification.kind === "unknown") {
    return "対応していない通知があります";
  }

  if (!notification.actorUsername) {
    switch (notification.notificationType) {
      case "exchange_invitation":
        return "交換日記への招待が届きました";
      case "exchange_invitation_accepted":
        return "交換日記への招待が承認されました";
      case "exchange_entry":
        return "交換日記が更新されました";
      default:
        return "この通知の送信者を現在表示できません";
    }
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
    case "exchange_invitation":
      return `${username}さんから交換日記に招待されました`;
    case "exchange_invitation_accepted":
      return `${username}さんが交換日記への招待を承認しました`;
    case "exchange_entry":
      return `${username}さんが交換日記を書きました`;
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
    <section className="flex flex-1 px-4 pb-8 pt-4 sm:px-8 sm:pb-10 sm:pt-6 lg:py-10">
      <div className="mx-auto w-full max-w-5xl min-w-0">
        <ActionLink className="-ml-3" href="/home" variant="quiet">
          ← ホームへ戻る
        </ActionLink>

        <div className="max-w-2xl min-w-0">
          <PageHeader
            className="mt-3"
            description="フォロー、リアクション、コメント、返信、交換日記のお知らせを新しい順に確認できます。"
            eyebrow="あなたへのお知らせ"
            title="通知"
            variant="plain"
          />
        </div>

        {!hasInvalidCursor && !hasLoadError && (
          <div className="mt-5 flex min-w-0 flex-wrap items-center justify-between gap-2 border-y border-border-subtle/70 py-3">
            <div className="flex min-w-0 items-center gap-2">
              <span
                aria-hidden="true"
                className="size-2 shrink-0 rounded-full bg-brand-primary"
              />
              <p
                aria-live="polite"
                className="min-w-0 break-words text-sm font-medium text-text-secondary [overflow-wrap:anywhere]"
              >
                未読 {unreadCount.toLocaleString("ja-JP")}件
              </p>
            </div>
            {unreadCount > 0 && <MarkAllNotificationsReadAction />}
          </div>
        )}

        {hasInvalidCursor ? (
          <FeedbackPanel
            className="mt-6 max-w-2xl"
            role="alert"
            title="ページ情報を確認できませんでした"
            variant="error"
          >
            <p>
              URLを確認するか、通知一覧の最初からもう一度お試しください。
            </p>
            <ActionLink
              className="mt-4"
              href="/notifications"
              variant="neutral"
            >
              通知一覧の最初へ戻る
            </ActionLink>
          </FeedbackPanel>
        ) : hasLoadError ? (
          <FeedbackPanel
            className="mt-6 max-w-2xl"
            role="alert"
            title="通知を読み込めませんでした"
            variant="error"
          >
            時間をおいて、もう一度お試しください。
          </FeedbackPanel>
        ) : notificationsResult?.data &&
          notificationsResult.data.length > 0 ? (
          <>
            <Surface
              as="section"
              aria-labelledby="notification-list-title"
              className="mt-6 overflow-hidden border border-border-subtle/70 shadow-surface"
              variant="elevated"
            >
              <h2 className="sr-only" id="notification-list-title">
                通知一覧
              </h2>
              <ul className="divide-y divide-border-subtle/70">
                {notificationsResult.data.map((notification) => {
                  const message = getNotificationMessage(notification);
                  const actorInitial = notification.actorUsername
                    ? (Array.from(notification.actorUsername.trim())[0] ??
                      "人")
                    : null;

                  return (
                    <li className="min-w-0" key={notification.id}>
                      <article
                        aria-label={`${message}、${notification.isRead ? "既読" : "未読"}`}
                        className={`min-w-0 px-4 py-5 sm:px-6 sm:py-6 ${
                          notification.isRead
                            ? "bg-surface-elevated"
                            : "bg-brand-soft/35"
                        }`}
                      >
                        <div className="flex min-w-0 items-start gap-3 sm:gap-4">
                          <span
                            aria-hidden="true"
                            className="flex size-11 shrink-0 items-center justify-center rounded-full bg-surface-muted text-base font-semibold text-brand-primary-hover"
                          >
                            {actorInitial ?? (
                              <svg
                                className="size-5"
                                fill="none"
                                focusable="false"
                                stroke="currentColor"
                                strokeLinecap="round"
                                strokeLinejoin="round"
                                strokeWidth="1.8"
                                viewBox="0 0 24 24"
                              >
                                <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" />
                                <path d="M10 21h4" />
                              </svg>
                            )}
                          </span>

                          <div className="min-w-0 flex-1">
                            <div className="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
                              <span
                                className={
                                  notification.isRead
                                    ? "inline-flex min-h-7 items-center text-xs font-medium text-text-muted"
                                    : "inline-flex min-h-7 items-center gap-1.5 rounded-full bg-surface-elevated/80 px-2.5 text-xs font-semibold text-brand-primary-hover"
                                }
                              >
                                {!notification.isRead && (
                                  <span
                                    aria-hidden="true"
                                    className="size-1.5 rounded-full bg-brand-primary"
                                  />
                                )}
                                {notification.isRead ? "既読" : "未読"}
                              </span>
                              <time
                                className="break-words text-xs text-text-muted [overflow-wrap:anywhere]"
                                dateTime={notification.createdAt}
                              >
                                {dateFormatter.format(
                                  new Date(notification.createdAt),
                                )}
                              </time>
                            </div>

                            <p className="mt-2 min-w-0 break-words text-[15px] font-medium leading-7 text-text-primary [overflow-wrap:anywhere] sm:text-base">
                              {message}
                            </p>

                            {notification.targetBehavior ===
                              "unavailable" && (
                              <p className="mt-2 break-words text-sm leading-6 text-text-muted [overflow-wrap:anywhere]">
                                この通知の対象は現在表示できません。
                              </p>
                            )}

                            {(notification.targetBehavior === "open" ||
                              !notification.isRead) && (
                              <div className="mt-3 flex min-w-0 flex-wrap items-start gap-1 sm:gap-2">
                                {notification.targetBehavior === "open" && (
                                  <NotificationOpenAction
                                    notificationId={notification.id}
                                    notificationLabel={message}
                                  />
                                )}
                                {!notification.isRead && (
                                  <NotificationReadAction
                                    notificationId={notification.id}
                                    notificationLabel={message}
                                  />
                                )}
                              </div>
                            )}
                          </div>
                        </div>
                      </article>
                    </li>
                  );
                })}
              </ul>
            </Surface>

            {notificationsResult.nextCursor && (
              <Pagination
                aria-label="通知一覧のページ移動"
                className="mt-6"
              >
                <PaginationLink
                  className="w-full sm:w-auto"
                  href={`/notifications?cursor=${encodeURIComponent(notificationsResult.nextCursor)}`}
                >
                  <span>次の通知を見る</span>
                  <span aria-hidden="true">→</span>
                </PaginationLink>
              </Pagination>
            )}

            {!notificationsResult.nextCursor && cursor && (
              <p className="mt-6 text-center text-sm text-text-muted">
                現在表示できる通知をすべて表示しました。
              </p>
            )}
          </>
        ) : cursor ? (
          <EmptyState
            action={
              <ActionLink href="/notifications" variant="neutral">
                通知一覧の最初へ戻る
              </ActionLink>
            }
            className="mt-6 max-w-2xl"
            title="次の通知はありません"
          />
        ) : (
          <EmptyState
            className="mt-6 max-w-2xl"
            description="フォローやリアクション、コメントがあるとここに表示されます。"
            title="まだ通知はありません"
          />
        )}
      </div>
    </section>
  );
}
