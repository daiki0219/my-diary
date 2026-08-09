import type { SupabaseClient } from "@supabase/supabase-js";

import { isUuid } from "@/lib/profile-data";

export const NOTIFICATION_PAGE_SIZE = 20;

const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;
const NOTIFICATION_DATA_ERROR = new Error(
  "Notification data shape is invalid.",
);

export type NotificationType = "follow" | "reaction" | "comment" | "reply";

export type NotificationCursor = {
  created_at: string;
  id: string;
};

export type NotificationListItem = {
  id: string;
  actorUsername: string | null;
  notificationType: NotificationType;
  isRead: boolean;
  createdAt: string;
  targetAvailable: boolean;
};

type NotificationRow = {
  id: string;
  actor_user_id: string;
  notification_type: NotificationType;
  target_post_id: string | null;
  target_comment_id: string | null;
  is_read: boolean;
  created_at: string;
};

type ActorProfileRow = {
  user_id: string;
  username: string;
};

function hasExactKeys(value: object, expectedKeys: readonly string[]) {
  const keys = Object.keys(value);

  return (
    keys.length === expectedKeys.length &&
    expectedKeys.every((key) => keys.includes(key))
  );
}

function canonicalizeTimestamp(value: string) {
  const date = new Date(value);

  if (!Number.isFinite(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function decodeOpaqueCursor(value: string): unknown | null {
  if (
    value.length === 0 ||
    value.length > CURSOR_MAX_LENGTH ||
    !CURSOR_CHARACTER_PATTERN.test(value)
  ) {
    return null;
  }

  try {
    const bytes = Buffer.from(value, "base64url");

    if (bytes.toString("base64url") !== value) {
      return null;
    }

    const json = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return JSON.parse(json) as unknown;
  } catch {
    return null;
  }
}

function isNotificationType(value: unknown): value is NotificationType {
  return (
    value === "follow" ||
    value === "reaction" ||
    value === "comment" ||
    value === "reply"
  );
}

function isNullableUuid(value: unknown): value is string | null {
  return value === null || (typeof value === "string" && isUuid(value));
}

function isNotificationRow(value: unknown): value is NotificationRow {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("actor_user_id" in value) ||
    !("notification_type" in value) ||
    !("target_post_id" in value) ||
    !("target_comment_id" in value) ||
    !("is_read" in value) ||
    !("created_at" in value) ||
    typeof value.id !== "string" ||
    typeof value.actor_user_id !== "string" ||
    !isNotificationType(value.notification_type) ||
    !isNullableUuid(value.target_post_id) ||
    !isNullableUuid(value.target_comment_id) ||
    typeof value.is_read !== "boolean" ||
    typeof value.created_at !== "string" ||
    !isUuid(value.id) ||
    !isUuid(value.actor_user_id) ||
    canonicalizeTimestamp(value.created_at) === null
  ) {
    return false;
  }

  if (value.notification_type === "follow") {
    return value.target_post_id === null && value.target_comment_id === null;
  }

  if (value.notification_type === "reaction") {
    return value.target_post_id !== null && value.target_comment_id === null;
  }

  return value.target_post_id !== null && value.target_comment_id !== null;
}

function isActorProfileRow(value: unknown): value is ActorProfileRow {
  return (
    typeof value === "object" &&
    value !== null &&
    "user_id" in value &&
    "username" in value &&
    typeof value.user_id === "string" &&
    typeof value.username === "string" &&
    isUuid(value.user_id) &&
    value.username.trim().length > 0
  );
}

export function encodeNotificationCursor(cursor: NotificationCursor) {
  const createdAt = canonicalizeTimestamp(cursor.created_at);

  if (!createdAt || !isUuid(cursor.id)) {
    throw new Error("Cannot encode an invalid notification cursor.");
  }

  return Buffer.from(
    JSON.stringify({
      created_at: createdAt,
      id: cursor.id.toLowerCase(),
    }),
    "utf8",
  ).toString("base64url");
}

export function decodeNotificationCursor(
  value: string,
): NotificationCursor | null {
  const cursor = decodeOpaqueCursor(value);

  if (
    typeof cursor !== "object" ||
    cursor === null ||
    !hasExactKeys(cursor, ["created_at", "id"]) ||
    !("created_at" in cursor) ||
    !("id" in cursor) ||
    typeof cursor.created_at !== "string" ||
    typeof cursor.id !== "string" ||
    cursor.id !== cursor.id.toLowerCase() ||
    !isUuid(cursor.id)
  ) {
    return null;
  }

  const createdAt = canonicalizeTimestamp(cursor.created_at);

  if (!createdAt || createdAt !== cursor.created_at) {
    return null;
  }

  return { created_at: createdAt, id: cursor.id };
}

export async function getNotifications(
  supabase: SupabaseClient,
  cursor: NotificationCursor | null,
) {
  let query = supabase
    .from("notifications")
    .select(
      "id, actor_user_id, notification_type, target_post_id, target_comment_id, is_read, created_at",
    )
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(NOTIFICATION_PAGE_SIZE + 1);

  if (cursor) {
    query = query.or(
      `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`,
    );
  }

  const notificationsResult = await query.returns<NotificationRow[]>();

  if (notificationsResult.error || !notificationsResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: notificationsResult.error,
    };
  }

  if (!notificationsResult.data.every(isNotificationRow)) {
    return { data: null, nextCursor: null, error: NOTIFICATION_DATA_ERROR };
  }

  const pageRows = notificationsResult.data.slice(0, NOTIFICATION_PAGE_SIZE);
  const actorIds = [...new Set(pageRows.map((row) => row.actor_user_id))];
  const targetCommentIds = [
    ...new Set(
      pageRows.flatMap((row) =>
        row.target_comment_id === null ? [] : [row.target_comment_id],
      ),
    ),
  ];

  const [profilesResult, commentsResult] = await Promise.all([
    actorIds.length > 0
      ? supabase
          .from("profiles")
          .select("user_id, username")
          .in("user_id", actorIds)
          .returns<ActorProfileRow[]>()
      : Promise.resolve({ data: [] as ActorProfileRow[], error: null }),
    targetCommentIds.length > 0
      ? supabase
          .from("comments")
          .select("id")
          .in("id", targetCommentIds)
          .returns<Array<{ id: string }>>()
      : Promise.resolve({ data: [] as Array<{ id: string }>, error: null }),
  ]);

  if (
    profilesResult.error ||
    commentsResult.error ||
    !profilesResult.data ||
    !commentsResult.data ||
    !profilesResult.data.every(isActorProfileRow) ||
    !commentsResult.data.every(
      (comment) =>
        typeof comment === "object" &&
        comment !== null &&
        typeof comment.id === "string" &&
        isUuid(comment.id),
    )
  ) {
    return { data: null, nextCursor: null, error: NOTIFICATION_DATA_ERROR };
  }

  const profilesByUserId = new Map(
    profilesResult.data.map((profile) => [profile.user_id, profile.username]),
  );
  const availableCommentIds = new Set(
    commentsResult.data.map((comment) => comment.id),
  );

  const data: NotificationListItem[] = pageRows.map((row) => {
    const actorUsername = profilesByUserId.get(row.actor_user_id) ?? null;
    const commentAvailable =
      row.target_comment_id === null ||
      availableCommentIds.has(row.target_comment_id);

    return {
      id: row.id,
      actorUsername,
      notificationType: row.notification_type,
      isRead: row.is_read,
      createdAt: row.created_at,
      targetAvailable: actorUsername !== null && commentAvailable,
    };
  });
  const lastNotification = pageRows.at(-1);
  const nextCursor =
    notificationsResult.data.length > NOTIFICATION_PAGE_SIZE &&
    lastNotification
      ? encodeNotificationCursor({
          created_at: lastNotification.created_at,
          id: lastNotification.id,
        })
      : null;

  return { data, nextCursor, error: null };
}

export async function getUnreadNotificationCount(
  supabase: SupabaseClient,
) {
  const result = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("is_read", false);

  if (result.error || result.count === null) {
    return { count: null, error: result.error ?? NOTIFICATION_DATA_ERROR };
  }

  return { count: result.count, error: null };
}

export async function getNotificationOpenTarget(
  supabase: SupabaseClient,
  notificationId: string,
) {
  const notificationResult = await supabase
    .from("notifications")
    .select(
      "id, actor_user_id, notification_type, target_post_id, target_comment_id, is_read, created_at",
    )
    .eq("id", notificationId)
    .limit(1)
    .maybeSingle<NotificationRow>();

  if (notificationResult.error) {
    return { data: null, error: notificationResult.error };
  }

  if (!notificationResult.data) {
    return { data: null, error: null };
  }

  if (!isNotificationRow(notificationResult.data)) {
    return { data: null, error: NOTIFICATION_DATA_ERROR };
  }

  const notification = notificationResult.data;
  const profileResult = await supabase
    .from("profiles")
    .select("user_id")
    .eq("user_id", notification.actor_user_id)
    .limit(1)
    .maybeSingle<{ user_id: string }>();

  if (profileResult.error) {
    return { data: null, error: profileResult.error };
  }

  let targetUrl: string | null = null;

  if (profileResult.data) {
    if (notification.notification_type === "follow") {
      targetUrl = `/users/${notification.actor_user_id}`;
    } else if (notification.notification_type === "reaction") {
      targetUrl = `/posts/${notification.target_post_id}`;
    } else if (notification.target_comment_id) {
      const commentResult = await supabase
        .from("comments")
        .select("id")
        .eq("id", notification.target_comment_id)
        .limit(1)
        .maybeSingle<{ id: string }>();

      if (commentResult.error) {
        return { data: null, error: commentResult.error };
      }

      if (commentResult.data) {
        targetUrl = `/posts/${notification.target_post_id}`;
      }
    }
  }

  return {
    data: { id: notification.id, targetUrl },
    error: null,
  };
}
