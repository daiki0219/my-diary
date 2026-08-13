import type { SupabaseClient } from "@supabase/supabase-js";

import {
  hydrateExchangeNotificationTargets,
  type ExchangeNotificationTarget,
  type ExchangeNotificationTargetReference,
} from "@/lib/exchange-data";
import { isUuid } from "@/lib/profile-data";

export const NOTIFICATION_PAGE_SIZE = 20;
export const KNOWN_NOTIFICATION_TYPES = [
  "follow",
  "reaction",
  "comment",
  "reply",
  "exchange_invitation",
  "exchange_invitation_accepted",
  "exchange_entry",
] as const;

const CURSOR_MAX_LENGTH = 512;
const CURSOR_CHARACTER_PATTERN = /^[A-Za-z0-9_-]+$/u;
const NOTIFICATION_DATA_ERROR = new Error(
  "Notification data shape is invalid.",
);

export type KnownNotificationType =
  (typeof KNOWN_NOTIFICATION_TYPES)[number];
export type NotificationType = KnownNotificationType;

export type NotificationCursor = {
  created_at: string;
  id: string;
};

type NotificationBaseRow = {
  id: string;
  recipient_user_id: string;
  actor_user_id: string;
  notification_type: string;
  target_post_id: string | null;
  target_comment_id: string | null;
  exchange_invitation_id: string | null;
  exchange_diary_id: string | null;
  exchange_entry_id: string | null;
  is_read: boolean;
  created_at: string;
};

type FollowNotificationRow = NotificationBaseRow & {
  kind: "known";
  notification_type: "follow";
  target_post_id: null;
  target_comment_id: null;
  exchange_invitation_id: null;
  exchange_diary_id: null;
  exchange_entry_id: null;
};

type ReactionNotificationRow = NotificationBaseRow & {
  kind: "known";
  notification_type: "reaction";
  target_post_id: string;
  target_comment_id: null;
  exchange_invitation_id: null;
  exchange_diary_id: null;
  exchange_entry_id: null;
};

type CommentNotificationRow = NotificationBaseRow & {
  kind: "known";
  notification_type: "comment" | "reply";
  target_post_id: string;
  target_comment_id: string;
  exchange_invitation_id: null;
  exchange_diary_id: null;
  exchange_entry_id: null;
};

type ExchangeInvitationNotificationRow = NotificationBaseRow & {
  kind: "known";
  notification_type: "exchange_invitation";
  target_post_id: null;
  target_comment_id: null;
  exchange_invitation_id: string;
  exchange_diary_id: null;
  exchange_entry_id: null;
};

type ExchangeAcceptedNotificationRow = NotificationBaseRow & {
  kind: "known";
  notification_type: "exchange_invitation_accepted";
  target_post_id: null;
  target_comment_id: null;
  exchange_invitation_id: string;
  exchange_diary_id: string;
  exchange_entry_id: null;
};

type ExchangeEntryNotificationRow = NotificationBaseRow & {
  kind: "known";
  notification_type: "exchange_entry";
  target_post_id: null;
  target_comment_id: null;
  exchange_invitation_id: null;
  exchange_diary_id: string;
  exchange_entry_id: string;
};

export type KnownNotificationRow =
  | FollowNotificationRow
  | ReactionNotificationRow
  | CommentNotificationRow
  | ExchangeInvitationNotificationRow
  | ExchangeAcceptedNotificationRow
  | ExchangeEntryNotificationRow;

export type UnknownNotificationRow = NotificationBaseRow & {
  kind: "unknown";
};

export type NotificationRow = KnownNotificationRow | UnknownNotificationRow;
export type NotificationTargetBehavior =
  | "open"
  | "unavailable"
  | "none";

type NotificationListItemBase = {
  id: string;
  actorUsername: string | null;
  isRead: boolean;
  createdAt: string;
};

export type KnownNotification = NotificationListItemBase & {
  kind: "known";
  notificationType: KnownNotificationType;
  targetBehavior: Exclude<NotificationTargetBehavior, "none">;
  exchangeTarget: ExchangeNotificationTarget | null;
};

export type UnknownNotification = NotificationListItemBase & {
  kind: "unknown";
  notificationType: string;
  actorUsername: null;
  targetBehavior: "none";
  exchangeTarget: null;
};

export type Notification = KnownNotification | UnknownNotification;
export type NotificationListItem = Notification;

type ActorProfileRow = {
  user_id: string;
  username: string;
};

const NOTIFICATION_SELECT = [
  "id",
  "recipient_user_id",
  "actor_user_id",
  "notification_type",
  "target_post_id",
  "target_comment_id",
  "exchange_invitation_id",
  "exchange_diary_id",
  "exchange_entry_id",
  "is_read",
  "created_at",
].join(", ");

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

export function isKnownNotificationType(
  value: string,
): value is KnownNotificationType {
  return KNOWN_NOTIFICATION_TYPES.some(
    (notificationType) => notificationType === value,
  );
}

function isNullableUuid(value: unknown): value is string | null {
  return value === null || (typeof value === "string" && isUuid(value));
}

function parseNotificationBaseRow(value: unknown): NotificationBaseRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("recipient_user_id" in value) ||
    !("actor_user_id" in value) ||
    !("notification_type" in value) ||
    !("target_post_id" in value) ||
    !("target_comment_id" in value) ||
    !("exchange_invitation_id" in value) ||
    !("exchange_diary_id" in value) ||
    !("exchange_entry_id" in value) ||
    !("is_read" in value) ||
    !("created_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.recipient_user_id !== "string" ||
    !isUuid(value.recipient_user_id) ||
    typeof value.actor_user_id !== "string" ||
    !isUuid(value.actor_user_id) ||
    value.actor_user_id.toLowerCase() === value.recipient_user_id.toLowerCase() ||
    typeof value.notification_type !== "string" ||
    value.notification_type.trim().length === 0 ||
    !isNullableUuid(value.target_post_id) ||
    !isNullableUuid(value.target_comment_id) ||
    !isNullableUuid(value.exchange_invitation_id) ||
    !isNullableUuid(value.exchange_diary_id) ||
    !isNullableUuid(value.exchange_entry_id) ||
    typeof value.is_read !== "boolean" ||
    typeof value.created_at !== "string" ||
    canonicalizeTimestamp(value.created_at) === null
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    recipient_user_id: value.recipient_user_id.toLowerCase(),
    actor_user_id: value.actor_user_id.toLowerCase(),
    notification_type: value.notification_type,
    target_post_id: value.target_post_id?.toLowerCase() ?? null,
    target_comment_id: value.target_comment_id?.toLowerCase() ?? null,
    exchange_invitation_id:
      value.exchange_invitation_id?.toLowerCase() ?? null,
    exchange_diary_id: value.exchange_diary_id?.toLowerCase() ?? null,
    exchange_entry_id: value.exchange_entry_id?.toLowerCase() ?? null,
    is_read: value.is_read,
    created_at: value.created_at,
  };
}

export function parseNotificationRow(value: unknown): NotificationRow | null {
  const row = parseNotificationBaseRow(value);

  if (!row) {
    return null;
  }

  if (!isKnownNotificationType(row.notification_type)) {
    return { ...row, kind: "unknown" };
  }

  switch (row.notification_type) {
    case "follow":
      return row.target_post_id === null &&
        row.target_comment_id === null &&
        row.exchange_invitation_id === null &&
        row.exchange_diary_id === null &&
        row.exchange_entry_id === null
        ? {
            ...row,
            kind: "known",
            notification_type: "follow",
            target_post_id: null,
            target_comment_id: null,
            exchange_invitation_id: null,
            exchange_diary_id: null,
            exchange_entry_id: null,
          }
        : null;
    case "reaction":
      return row.target_post_id !== null &&
        row.target_comment_id === null &&
        row.exchange_invitation_id === null &&
        row.exchange_diary_id === null &&
        row.exchange_entry_id === null
        ? {
            ...row,
            kind: "known",
            notification_type: "reaction",
            target_post_id: row.target_post_id,
            target_comment_id: null,
            exchange_invitation_id: null,
            exchange_diary_id: null,
            exchange_entry_id: null,
          }
        : null;
    case "comment":
    case "reply":
      return row.target_post_id !== null &&
        row.target_comment_id !== null &&
        row.exchange_invitation_id === null &&
        row.exchange_diary_id === null &&
        row.exchange_entry_id === null
        ? {
            ...row,
            kind: "known",
            notification_type: row.notification_type,
            target_post_id: row.target_post_id,
            target_comment_id: row.target_comment_id,
            exchange_invitation_id: null,
            exchange_diary_id: null,
            exchange_entry_id: null,
          }
        : null;
    case "exchange_invitation":
      return row.target_post_id === null &&
        row.target_comment_id === null &&
        row.exchange_invitation_id !== null &&
        row.exchange_diary_id === null &&
        row.exchange_entry_id === null
        ? {
            ...row,
            kind: "known",
            notification_type: "exchange_invitation",
            target_post_id: null,
            target_comment_id: null,
            exchange_invitation_id: row.exchange_invitation_id,
            exchange_diary_id: null,
            exchange_entry_id: null,
          }
        : null;
    case "exchange_invitation_accepted":
      return row.target_post_id === null &&
        row.target_comment_id === null &&
        row.exchange_invitation_id !== null &&
        row.exchange_diary_id !== null &&
        row.exchange_entry_id === null
        ? {
            ...row,
            kind: "known",
            notification_type: "exchange_invitation_accepted",
            target_post_id: null,
            target_comment_id: null,
            exchange_invitation_id: row.exchange_invitation_id,
            exchange_diary_id: row.exchange_diary_id,
            exchange_entry_id: null,
          }
        : null;
    case "exchange_entry":
      return row.target_post_id === null &&
        row.target_comment_id === null &&
        row.exchange_invitation_id === null &&
        row.exchange_diary_id !== null &&
        row.exchange_entry_id !== null
        ? {
            ...row,
            kind: "known",
            notification_type: "exchange_entry",
            target_post_id: null,
            target_comment_id: null,
            exchange_invitation_id: null,
            exchange_diary_id: row.exchange_diary_id,
            exchange_entry_id: row.exchange_entry_id,
          }
        : null;
  }
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

function isExchangeNotificationRow(
  row: NotificationRow,
): row is
  | ExchangeInvitationNotificationRow
  | ExchangeAcceptedNotificationRow
  | ExchangeEntryNotificationRow {
  return (
    row.kind === "known" &&
    (row.notification_type === "exchange_invitation" ||
      row.notification_type === "exchange_invitation_accepted" ||
      row.notification_type === "exchange_entry")
  );
}

function toExchangeTargetReference(
  row:
    | ExchangeInvitationNotificationRow
    | ExchangeAcceptedNotificationRow
    | ExchangeEntryNotificationRow,
): ExchangeNotificationTargetReference {
  switch (row.notification_type) {
    case "exchange_invitation":
      return {
        notificationId: row.id,
        notificationType: row.notification_type,
        invitationId: row.exchange_invitation_id,
        diaryId: null,
        entryId: null,
      };
    case "exchange_invitation_accepted":
      return {
        notificationId: row.id,
        notificationType: row.notification_type,
        invitationId: row.exchange_invitation_id,
        diaryId: row.exchange_diary_id,
        entryId: null,
      };
    case "exchange_entry":
      return {
        notificationId: row.id,
        notificationType: row.notification_type,
        invitationId: null,
        diaryId: row.exchange_diary_id,
        entryId: row.exchange_entry_id,
      };
  }
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
    .select(NOTIFICATION_SELECT)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(NOTIFICATION_PAGE_SIZE + 1);

  if (cursor) {
    query = query.or(
      `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`,
    );
  }

  const notificationsResult = await query.returns<unknown[]>();

  if (notificationsResult.error || !notificationsResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: notificationsResult.error,
    };
  }

  const parsedRows: NotificationRow[] = [];

  for (const value of notificationsResult.data) {
    const row = parseNotificationRow(value);

    if (!row) {
      return { data: null, nextCursor: null, error: NOTIFICATION_DATA_ERROR };
    }

    parsedRows.push(row);
  }

  const pageRows = parsedRows.slice(0, NOTIFICATION_PAGE_SIZE);
  const knownRows = pageRows.filter(
    (row): row is KnownNotificationRow => row.kind === "known",
  );
  const actorIds = [...new Set(knownRows.map((row) => row.actor_user_id))];
  const targetCommentIds = [
    ...new Set(
      knownRows.flatMap((row) =>
        row.notification_type === "comment" ||
        row.notification_type === "reply"
          ? [row.target_comment_id]
          : [],
      ),
    ),
  ];
  const exchangeRows = pageRows.filter(isExchangeNotificationRow);
  const [profilesResult, commentsResult, exchangeTargetsResult] =
    await Promise.all([
      actorIds.length > 0
        ? supabase
            .from("profiles")
            .select("user_id, username")
            .in("user_id", actorIds)
            .returns<unknown[]>()
        : Promise.resolve({ data: [] as unknown[], error: null }),
      targetCommentIds.length > 0
        ? supabase
            .from("comments")
            .select("id")
            .in("id", targetCommentIds)
            .returns<unknown[]>()
        : Promise.resolve({ data: [] as unknown[], error: null }),
      hydrateExchangeNotificationTargets(
        supabase,
        exchangeRows.map(toExchangeTargetReference),
      ),
    ]);

  if (
    profilesResult.error ||
    commentsResult.error ||
    exchangeTargetsResult.error ||
    !profilesResult.data ||
    !commentsResult.data ||
    !exchangeTargetsResult.data ||
    !profilesResult.data.every(isActorProfileRow) ||
    !commentsResult.data.every(
      (comment) =>
        typeof comment === "object" &&
        comment !== null &&
        "id" in comment &&
        typeof comment.id === "string" &&
        isUuid(comment.id),
    ) ||
    exchangeRows.some((row) => !exchangeTargetsResult.data?.has(row.id))
  ) {
    return { data: null, nextCursor: null, error: NOTIFICATION_DATA_ERROR };
  }

  const profilesByUserId = new Map(
    profilesResult.data.map((profile) => [
      profile.user_id.toLowerCase(),
      profile.username,
    ]),
  );
  const availableCommentIds = new Set(
    commentsResult.data.flatMap((comment) =>
      typeof comment === "object" &&
      comment !== null &&
      "id" in comment &&
      typeof comment.id === "string"
        ? [comment.id.toLowerCase()]
        : [],
    ),
  );
  const data: NotificationListItem[] = [];

  for (const row of pageRows) {
    if (row.kind === "unknown") {
      data.push({
        id: row.id,
        kind: "unknown",
        actorUsername: null,
        notificationType: row.notification_type,
        isRead: row.is_read,
        createdAt: row.created_at,
        targetBehavior: "none",
        exchangeTarget: null,
      });
      continue;
    }

    const actorUsername = profilesByUserId.get(row.actor_user_id) ?? null;

    if (isExchangeNotificationRow(row)) {
      const exchangeTarget = exchangeTargetsResult.data.get(row.id);

      if (!exchangeTarget) {
        return { data: null, nextCursor: null, error: NOTIFICATION_DATA_ERROR };
      }

      data.push({
        id: row.id,
        kind: "known",
        actorUsername,
        notificationType: row.notification_type,
        isRead: row.is_read,
        createdAt: row.created_at,
        targetBehavior: exchangeTarget.futureTargetAvailable
          ? "open"
          : "unavailable",
        exchangeTarget,
      });
      continue;
    }

    const commentAvailable =
      row.notification_type === "comment" || row.notification_type === "reply"
        ? availableCommentIds.has(row.target_comment_id)
        : true;

    data.push({
      id: row.id,
      kind: "known",
      actorUsername,
      notificationType: row.notification_type,
      isRead: row.is_read,
      createdAt: row.created_at,
      targetBehavior:
        actorUsername !== null && commentAvailable ? "open" : "unavailable",
      exchangeTarget: null,
    });
  }

  const lastNotification = pageRows.at(-1);
  const nextCursor =
    parsedRows.length > NOTIFICATION_PAGE_SIZE && lastNotification
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
    .select(NOTIFICATION_SELECT)
    .eq("id", notificationId)
    .limit(1)
    .maybeSingle<unknown>();

  if (notificationResult.error) {
    return { data: null, error: notificationResult.error };
  }

  if (!notificationResult.data) {
    return { data: null, error: null };
  }

  const notification = parseNotificationRow(notificationResult.data);

  if (!notification) {
    return { data: null, error: NOTIFICATION_DATA_ERROR };
  }

  if (notification.kind === "unknown") {
    return {
      data: { id: notification.id, targetUrl: null },
      error: null,
    };
  }

  if (isExchangeNotificationRow(notification)) {
    const targetsResult = await hydrateExchangeNotificationTargets(supabase, [
      toExchangeTargetReference(notification),
    ]);

    if (targetsResult.error || !targetsResult.data) {
      return {
        data: null,
        error: targetsResult.error ?? NOTIFICATION_DATA_ERROR,
      };
    }

    const target = targetsResult.data.get(notification.id);

    if (!target) {
      return { data: null, error: NOTIFICATION_DATA_ERROR };
    }

    let targetUrl: string | null = null;

    if (target.kind === "invitation") {
      if (target.state === "pending") {
        targetUrl = "/exchange?view=invitations";
      } else if (
        target.state === "accepted" &&
        target.futureTargetAvailable
      ) {
        targetUrl = `/exchange/${target.diaryId}`;
      }
    } else if (
      target.kind === "diary" &&
      target.futureTargetAvailable
    ) {
      targetUrl = `/exchange/${target.diaryId}`;
    } else if (
      target.kind === "entry" &&
      target.futureTargetAvailable
    ) {
      targetUrl = `/exchange/${target.diaryId}?view=latest`;
    }

    return {
      data: { id: notification.id, targetUrl },
      error: null,
    };
  }

  const profileResult = await supabase
    .from("profiles")
    .select("user_id")
    .eq("user_id", notification.actor_user_id)
    .limit(1)
    .maybeSingle<unknown>();

  if (profileResult.error) {
    return { data: null, error: profileResult.error };
  }

  const profileAvailable =
    typeof profileResult.data === "object" &&
    profileResult.data !== null &&
    "user_id" in profileResult.data &&
    typeof profileResult.data.user_id === "string" &&
    isUuid(profileResult.data.user_id);

  if (profileResult.data !== null && !profileAvailable) {
    return { data: null, error: NOTIFICATION_DATA_ERROR };
  }
  let targetUrl: string | null = null;

  if (profileAvailable) {
    switch (notification.notification_type) {
      case "follow":
        targetUrl = `/users/${notification.actor_user_id}`;
        break;
      case "reaction":
        targetUrl = `/posts/${notification.target_post_id}`;
        break;
      case "comment":
      case "reply": {
        const commentResult = await supabase
          .from("comments")
          .select("id")
          .eq("id", notification.target_comment_id)
          .limit(1)
          .maybeSingle<unknown>();

        if (commentResult.error) {
          return { data: null, error: commentResult.error };
        }

        const commentAvailable =
          typeof commentResult.data === "object" &&
          commentResult.data !== null &&
          "id" in commentResult.data &&
          typeof commentResult.data.id === "string" &&
          isUuid(commentResult.data.id);

        if (commentResult.data !== null && !commentAvailable) {
          return { data: null, error: NOTIFICATION_DATA_ERROR };
        }

        if (commentAvailable) {
          targetUrl = `/posts/${notification.target_post_id}`;
        }
        break;
      }
    }
  }

  return {
    data: { id: notification.id, targetUrl },
    error: null,
  };
}
