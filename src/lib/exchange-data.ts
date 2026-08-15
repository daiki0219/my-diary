import type { SupabaseClient } from "@supabase/supabase-js";

import {
  canonicalizeExchangeUuid,
  encodeExchangeEntryCursor,
  encodeExchangeTopCursor,
  type ExchangeEntryCursor,
  type ExchangeEntryMode,
  type ExchangeTopCursor,
} from "@/lib/exchange-cursor";
import {
  getExchangeEntryImagesByEntryIds,
  type ExchangeEntryImageReference,
} from "@/lib/exchange-entry-image-data";
import { isUuid } from "@/lib/profile-data";
import { isPostSearchTimestamp } from "@/lib/search-cursor";

export const EXCHANGE_PAGE_SIZE = 20;

const EXCHANGE_DATA_ERROR = new Error("Exchange data shape is invalid.");
const EXCHANGE_MOODS = [
  "happy",
  "sad",
  "tired",
  "irritated",
  "calm",
  "neutral",
] as const;

type ExchangeMood = (typeof EXCHANGE_MOODS)[number];
type ExchangeDiaryState = "active" | "archived";

export type ExchangeProfile = {
  userId: string;
  username: string;
};

export type ExchangeParticipant = {
  participantId: string;
  position: 1 | 2;
  userId: string | null;
  joinedAt: string;
  profile: ExchangeProfile | null;
};

export type ExchangeDiaryListItem = {
  diaryId: string;
  title: string | null;
  state: ExchangeDiaryState;
  startedAt: string;
  createdAt: string;
  archivedAt: string | null;
  participants: [ExchangeParticipant, ExchangeParticipant];
  counterpart: ExchangeParticipant;
};

export type PendingExchangeInvitation = {
  invitationId: string;
  inviterUserId: string;
  inviteeUserId: string;
  createdAt: string;
  direction: "sent" | "received";
  counterpartUserId: string;
  counterpartProfile: ExchangeProfile | null;
};

export type ExchangeProfileContext = {
  isMutualFollowing: boolean;
  pendingDirection: "sent" | "received" | null;
  isBlockingInvitations: boolean;
};

export type ExchangeDiaryDetail = {
  diaryId: string;
  title: string | null;
  state: ExchangeDiaryState;
  startedAt: string;
  createdAt: string;
  archivedAt: string | null;
  participants: [ExchangeParticipant, ExchangeParticipant];
  viewerParticipant: ExchangeParticipant;
  counterpart: ExchangeParticipant;
};

export type ExchangeEntryTag = {
  tagId: string;
  name: string;
};

export type ExchangeActiveEntry = {
  kind: "active";
  entryId: string;
  diaryId: string;
  authorParticipantId: string;
  title: string | null;
  body: string;
  mood: ExchangeMood | null;
  locationName: string | null;
  createdAt: string;
  tags: ExchangeEntryTag[];
  images: ExchangeEntryImageReference[];
};

export type ExchangeDeletedEntry = {
  kind: "deleted";
  entryId: string;
  diaryId: string;
  authorParticipantId: string;
  createdAt: string;
  deletedAt: string;
};

export type ExchangeEntry = ExchangeActiveEntry | ExchangeDeletedEntry;

export type LatestExchangeEntry = {
  entryId: string;
  diaryId: string;
  authorParticipantId: string;
  createdAt: string;
  deleted: boolean;
};

type DiaryRow = {
  id: string;
  title: string | null;
  state: ExchangeDiaryState;
  started_at: string;
  archived_at: string | null;
  created_at: string;
};

type ParticipantRow = {
  id: string;
  diary_id: string;
  position: 1 | 2;
  user_id: string | null;
  joined_at: string;
};

type ProfileRow = {
  user_id: string;
  username: string;
};

type InvitationRow = {
  id: string;
  inviter_user_id: string;
  invitee_user_id: string;
  status: "pending";
  created_at: string;
};

type ActiveEntryRow = Omit<ExchangeActiveEntry, "tags" | "images">;
type ParsedEntryRow = ActiveEntryRow | ExchangeDeletedEntry;

type TagRow = {
  entry_id: string;
  tag_id: string;
  name: string;
};

type InvitationTargetRow = {
  id: string;
  status: "pending" | "accepted" | "rejected" | "cancelled" | "invalidated";
  diary_id: string | null;
};

type EntryTargetRow = {
  id: string;
  diary_id: string;
  deleted_at: string | null;
};

export type ExchangeNotificationTargetReference =
  | {
      notificationId: string;
      notificationType: "exchange_invitation";
      invitationId: string;
      diaryId: null;
      entryId: null;
    }
  | {
      notificationId: string;
      notificationType: "exchange_invitation_accepted";
      invitationId: string;
      diaryId: string;
      entryId: null;
    }
  | {
      notificationId: string;
      notificationType: "exchange_entry";
      invitationId: null;
      diaryId: string;
      entryId: string;
    };

export type ExchangeNotificationTarget =
  | { kind: "invitation"; state: "pending"; futureTargetAvailable: true }
  | {
      kind: "invitation";
      state: "accepted";
      diaryId: string;
      futureTargetAvailable: boolean;
    }
  | {
      kind: "invitation";
      state: "terminal";
      futureTargetAvailable: false;
    }
  | {
      kind: "diary";
      diaryId: string;
      futureTargetAvailable: boolean;
    }
  | {
      kind: "entry";
      diaryId: string;
      entryId: string;
      entryState: "active" | "deleted" | "unavailable";
      futureTargetAvailable: boolean;
    }
  | { kind: "unavailable"; futureTargetAvailable: false };

function isTimestamp(value: unknown): value is string {
  return typeof value === "string" && isPostSearchTimestamp(value);
}

function isNullableUuid(value: unknown): value is string | null {
  return value === null || (typeof value === "string" && isUuid(value));
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isBoundedTrimmedString(value: string, maxLength: number) {
  const length = Array.from(value).length;
  return length >= 1 && length <= maxLength && value.trim() === value;
}

function isNullableBoundedTrimmedString(
  value: unknown,
  maxLength: number,
): value is string | null {
  return (
    value === null ||
    (typeof value === "string" && isBoundedTrimmedString(value, maxLength))
  );
}

function isExchangeMood(value: unknown): value is ExchangeMood {
  return (
    typeof value === "string" &&
    EXCHANGE_MOODS.some((mood) => mood === value)
  );
}

function parseDiaryRow(value: unknown): DiaryRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("title" in value) ||
    !("state" in value) ||
    !("started_at" in value) ||
    !("archived_at" in value) ||
    !("created_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    !isNullableBoundedTrimmedString(value.title, 120) ||
    (value.state !== "active" && value.state !== "archived") ||
    !isTimestamp(value.started_at) ||
    (value.archived_at !== null && !isTimestamp(value.archived_at)) ||
    !isTimestamp(value.created_at) ||
    (value.state === "active" && value.archived_at !== null) ||
    (value.state === "archived" && value.archived_at === null)
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    title: value.title,
    state: value.state,
    started_at: value.started_at,
    archived_at: value.archived_at,
    created_at: value.created_at,
  };
}

function parseParticipantRow(value: unknown): ParticipantRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("diary_id" in value) ||
    !("position" in value) ||
    !("user_id" in value) ||
    !("joined_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.diary_id !== "string" ||
    !isUuid(value.diary_id) ||
    (value.position !== 1 && value.position !== 2) ||
    !isNullableUuid(value.user_id) ||
    !isTimestamp(value.joined_at)
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    diary_id: value.diary_id.toLowerCase(),
    position: value.position,
    user_id: value.user_id?.toLowerCase() ?? null,
    joined_at: value.joined_at,
  };
}

function parseProfileRow(value: unknown): ProfileRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("user_id" in value) ||
    !("username" in value) ||
    typeof value.user_id !== "string" ||
    !isUuid(value.user_id) ||
    typeof value.username !== "string" ||
    !isBoundedTrimmedString(value.username, 50)
  ) {
    return null;
  }

  return {
    user_id: value.user_id.toLowerCase(),
    username: value.username,
  };
}

function parsePendingInvitationRow(value: unknown): InvitationRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("inviter_user_id" in value) ||
    !("invitee_user_id" in value) ||
    !("status" in value) ||
    !("created_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.inviter_user_id !== "string" ||
    !isUuid(value.inviter_user_id) ||
    typeof value.invitee_user_id !== "string" ||
    !isUuid(value.invitee_user_id) ||
    value.status !== "pending" ||
    !isTimestamp(value.created_at)
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    inviter_user_id: value.inviter_user_id.toLowerCase(),
    invitee_user_id: value.invitee_user_id.toLowerCase(),
    status: "pending",
    created_at: value.created_at,
  };
}

function parseEntryRow(value: unknown): ParsedEntryRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("diary_id" in value) ||
    !("author_participant_id" in value) ||
    !("title" in value) ||
    !("body" in value) ||
    !("mood" in value) ||
    !("location_name" in value) ||
    !("created_at" in value) ||
    !("deleted_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.diary_id !== "string" ||
    !isUuid(value.diary_id) ||
    typeof value.author_participant_id !== "string" ||
    !isUuid(value.author_participant_id) ||
    !isNullableBoundedTrimmedString(value.title, 120) ||
    !isNullableString(value.body) ||
    (value.mood !== null && !isExchangeMood(value.mood)) ||
    !isNullableBoundedTrimmedString(value.location_name, 100) ||
    !isTimestamp(value.created_at) ||
    (value.deleted_at !== null && !isTimestamp(value.deleted_at))
  ) {
    return null;
  }

  const common = {
    entryId: value.id.toLowerCase(),
    diaryId: value.diary_id.toLowerCase(),
    authorParticipantId: value.author_participant_id.toLowerCase(),
    createdAt: value.created_at,
  };

  if (value.deleted_at !== null) {
    if (
      value.title !== null ||
      value.body !== null ||
      value.mood !== null ||
      value.location_name !== null
    ) {
      return null;
    }

    return {
      kind: "deleted",
      ...common,
      deletedAt: value.deleted_at,
    };
  }

  if (
    value.body === null ||
    !isBoundedTrimmedString(value.body, 10_000)
  ) {
    return null;
  }

  return {
    kind: "active",
    ...common,
    title: value.title,
    body: value.body,
    mood: value.mood,
    locationName: value.location_name,
  };
}

function parseTagRow(value: unknown): TagRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("entry_id" in value) ||
    !("tag_id" in value) ||
    !("name" in value) ||
    typeof value.entry_id !== "string" ||
    !isUuid(value.entry_id) ||
    typeof value.tag_id !== "string" ||
    !isUuid(value.tag_id) ||
    typeof value.name !== "string" ||
    !isBoundedTrimmedString(value.name, 30)
  ) {
    return null;
  }

  return {
    entry_id: value.entry_id.toLowerCase(),
    tag_id: value.tag_id.toLowerCase(),
    name: value.name,
  };
}

async function hydrateParticipants(
  supabase: SupabaseClient,
  diaryIds: string[],
) {
  if (diaryIds.length === 0) {
    return {
      participantsByDiaryId: new Map<
        string,
        [ExchangeParticipant, ExchangeParticipant]
      >(),
      error: null,
    };
  }

  const participantsResult = await supabase
    .from("exchange_diary_participants")
    .select("id, diary_id, position, user_id, joined_at")
    .in("diary_id", diaryIds)
    .order("diary_id", { ascending: true })
    .order("position", { ascending: true })
    .returns<unknown[]>();

  if (participantsResult.error || !participantsResult.data) {
    return {
      participantsByDiaryId: null,
      error: participantsResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const participantRows: ParticipantRow[] = [];

  for (const value of participantsResult.data) {
    const participant = parseParticipantRow(value);

    if (!participant || !diaryIds.includes(participant.diary_id)) {
      return { participantsByDiaryId: null, error: EXCHANGE_DATA_ERROR };
    }

    participantRows.push(participant);
  }

  const userIds = [
    ...new Set(
      participantRows.flatMap((participant) =>
        participant.user_id ? [participant.user_id] : [],
      ),
    ),
  ];
  const profilesResult =
    userIds.length > 0
      ? await supabase
          .from("profiles")
          .select("user_id, username")
          .in("user_id", userIds)
          .returns<unknown[]>()
      : { data: [] as unknown[], error: null };

  if (profilesResult.error || !profilesResult.data) {
    return {
      participantsByDiaryId: null,
      error: profilesResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const profilesByUserId = new Map<string, ExchangeProfile>();

  for (const value of profilesResult.data) {
    const profile = parseProfileRow(value);

    if (!profile || !userIds.includes(profile.user_id)) {
      return { participantsByDiaryId: null, error: EXCHANGE_DATA_ERROR };
    }

    profilesByUserId.set(profile.user_id, {
      userId: profile.user_id,
      username: profile.username,
    });
  }

  const rowsByDiaryId = new Map<string, ParticipantRow[]>();

  for (const participant of participantRows) {
    const rows = rowsByDiaryId.get(participant.diary_id) ?? [];
    rows.push(participant);
    rowsByDiaryId.set(participant.diary_id, rows);
  }

  const participantsByDiaryId = new Map<
    string,
    [ExchangeParticipant, ExchangeParticipant]
  >();

  for (const diaryId of diaryIds) {
    const rows = rowsByDiaryId.get(diaryId);

    if (
      !rows ||
      rows.length !== 2 ||
      rows[0]?.position !== 1 ||
      rows[1]?.position !== 2
    ) {
      return { participantsByDiaryId: null, error: EXCHANGE_DATA_ERROR };
    }

    const toParticipant = (row: ParticipantRow): ExchangeParticipant => ({
      participantId: row.id,
      position: row.position,
      userId: row.user_id,
      joinedAt: row.joined_at,
      profile: row.user_id
        ? (profilesByUserId.get(row.user_id) ?? null)
        : null,
    });
    const firstParticipant = rows[0];
    const secondParticipant = rows[1];

    if (!firstParticipant || !secondParticipant) {
      return { participantsByDiaryId: null, error: EXCHANGE_DATA_ERROR };
    }

    const participants: [ExchangeParticipant, ExchangeParticipant] = [
      toParticipant(firstParticipant),
      toParticipant(secondParticipant),
    ];

    participantsByDiaryId.set(diaryId, participants);
  }

  return { participantsByDiaryId, error: null };
}

function getViewerParticipants(
  participants: [ExchangeParticipant, ExchangeParticipant],
  viewerUserId: string,
) {
  const viewerId = canonicalizeExchangeUuid(viewerUserId);

  if (!viewerId) {
    return null;
  }

  const viewerParticipant = participants.find(
    (participant) => participant.userId === viewerId,
  );
  const counterpart = participants.find(
    (participant) => participant.participantId !== viewerParticipant?.participantId,
  );

  return viewerParticipant && counterpart
    ? { viewerParticipant, counterpart }
    : null;
}

export async function getExchangeDiaryListPage(
  supabase: SupabaseClient,
  viewerUserId: string,
  state: ExchangeDiaryState,
  cursor: ExchangeTopCursor | null,
) {
  if (cursor && cursor.view !== state) {
    return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
  }

  let query = supabase
    .from("exchange_diaries")
    .select(
      "id, title, state, started_at, archived_at, created_at",
    )
    .eq("state", state)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(EXCHANGE_PAGE_SIZE + 1);

  if (cursor) {
    query = query.or(
      `created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`,
    );
  }

  const diariesResult = await query.returns<unknown[]>();

  if (diariesResult.error || !diariesResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: diariesResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const parsedDiaries: DiaryRow[] = [];

  for (const value of diariesResult.data) {
    const diary = parseDiaryRow(value);

    if (!diary || diary.state !== state) {
      return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
    }

    parsedDiaries.push(diary);
  }

  const pageDiaries = parsedDiaries.slice(0, EXCHANGE_PAGE_SIZE);
  const participantResult = await hydrateParticipants(
    supabase,
    pageDiaries.map((diary) => diary.id),
  );

  if (participantResult.error || !participantResult.participantsByDiaryId) {
    return {
      data: null,
      nextCursor: null,
      error: participantResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const data: ExchangeDiaryListItem[] = [];

  for (const diary of pageDiaries) {
    const participants = participantResult.participantsByDiaryId.get(diary.id);
    const viewerParticipants = participants
      ? getViewerParticipants(participants, viewerUserId)
      : null;

    if (!participants || !viewerParticipants) {
      return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
    }

    data.push({
      diaryId: diary.id,
      title: diary.title,
      state: diary.state,
      startedAt: diary.started_at,
      createdAt: diary.created_at,
      archivedAt: diary.archived_at,
      participants,
      counterpart: viewerParticipants.counterpart,
    });
  }

  const lastDiary = pageDiaries.at(-1);
  const nextCursor =
    parsedDiaries.length > EXCHANGE_PAGE_SIZE && lastDiary
      ? encodeExchangeTopCursor({
          view: state,
          createdAt: lastDiary.created_at,
          id: lastDiary.id,
        })
      : null;

  return { data, nextCursor, error: null };
}

export async function getPendingExchangeInvitationsPage(
  supabase: SupabaseClient,
  viewerUserId: string,
  cursor: ExchangeTopCursor | null,
) {
  const viewerId = canonicalizeExchangeUuid(viewerUserId);

  if (!viewerId || (cursor && cursor.view !== "invitations")) {
    return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
  }

  let query = supabase
    .from("exchange_invitations")
    .select("id, inviter_user_id, invitee_user_id, status, created_at")
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(EXCHANGE_PAGE_SIZE + 1);

  if (cursor) {
    query = query.or(
      `created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id})`,
    );
  }

  const invitationsResult = await query.returns<unknown[]>();

  if (invitationsResult.error || !invitationsResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: invitationsResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const invitations: InvitationRow[] = [];

  for (const value of invitationsResult.data) {
    const invitation = parsePendingInvitationRow(value);

    if (!invitation) {
      return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
    }

    invitations.push(invitation);
  }

  const pageInvitations = invitations.slice(0, EXCHANGE_PAGE_SIZE);
  const counterpartIds: string[] = [];

  for (const invitation of pageInvitations) {
    if (
      invitation.inviter_user_id !== viewerId &&
      invitation.invitee_user_id !== viewerId
    ) {
      return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
    }

    counterpartIds.push(
      invitation.inviter_user_id === viewerId
        ? invitation.invitee_user_id
        : invitation.inviter_user_id,
    );
  }

  const uniqueCounterpartIds = [...new Set(counterpartIds)];
  const profilesResult =
    uniqueCounterpartIds.length > 0
      ? await supabase
          .from("profiles")
          .select("user_id, username")
          .in("user_id", uniqueCounterpartIds)
          .returns<unknown[]>()
      : { data: [] as unknown[], error: null };

  if (profilesResult.error || !profilesResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: profilesResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const profilesByUserId = new Map<string, ExchangeProfile>();

  for (const value of profilesResult.data) {
    const profile = parseProfileRow(value);

    if (!profile || !uniqueCounterpartIds.includes(profile.user_id)) {
      return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
    }

    profilesByUserId.set(profile.user_id, {
      userId: profile.user_id,
      username: profile.username,
    });
  }

  const data: PendingExchangeInvitation[] = pageInvitations.map(
    (invitation) => {
      const sent = invitation.inviter_user_id === viewerId;
      const counterpartUserId = sent
        ? invitation.invitee_user_id
        : invitation.inviter_user_id;

      return {
        invitationId: invitation.id,
        inviterUserId: invitation.inviter_user_id,
        inviteeUserId: invitation.invitee_user_id,
        createdAt: invitation.created_at,
        direction: sent ? "sent" : "received",
        counterpartUserId,
        counterpartProfile: profilesByUserId.get(counterpartUserId) ?? null,
      };
    },
  );
  const lastInvitation = pageInvitations.at(-1);
  const nextCursor =
    invitations.length > EXCHANGE_PAGE_SIZE && lastInvitation
      ? encodeExchangeTopCursor({
          view: "invitations",
          createdAt: lastInvitation.created_at,
          id: lastInvitation.id,
        })
      : null;

  return { data, nextCursor, error: null };
}

export async function getExchangeProfileContext(
  supabase: SupabaseClient,
  viewerUserId: string,
  targetUserId: string,
) {
  const viewerId = canonicalizeExchangeUuid(viewerUserId);
  const targetId = canonicalizeExchangeUuid(targetUserId);

  if (!viewerId || !targetId || viewerId === targetId) {
    return { data: null, error: EXCHANGE_DATA_ERROR };
  }

  const [
    viewerFollowsResult,
    targetFollowsResult,
    sentInvitationResult,
    receivedInvitationResult,
    blockResult,
  ] = await Promise.all([
    supabase
      .from("follows")
      .select("follower_id, following_id")
      .eq("follower_id", viewerId)
      .eq("following_id", targetId)
      .limit(1)
      .maybeSingle<{ follower_id: string; following_id: string }>(),
    supabase
      .from("follows")
      .select("follower_id, following_id")
      .eq("follower_id", targetId)
      .eq("following_id", viewerId)
      .limit(1)
      .maybeSingle<{ follower_id: string; following_id: string }>(),
    supabase
      .from("exchange_invitations")
      .select("id, inviter_user_id, invitee_user_id")
      .eq("inviter_user_id", viewerId)
      .eq("invitee_user_id", targetId)
      .eq("status", "pending")
      .limit(1)
      .maybeSingle<{
        id: string;
        inviter_user_id: string;
        invitee_user_id: string;
      }>(),
    supabase
      .from("exchange_invitations")
      .select("id, inviter_user_id, invitee_user_id")
      .eq("inviter_user_id", targetId)
      .eq("invitee_user_id", viewerId)
      .eq("status", "pending")
      .limit(1)
      .maybeSingle<{
        id: string;
        inviter_user_id: string;
        invitee_user_id: string;
      }>(),
    supabase
      .from("exchange_invitation_blocks")
      .select("blocker_user_id, blocked_inviter_user_id")
      .eq("blocker_user_id", viewerId)
      .eq("blocked_inviter_user_id", targetId)
      .limit(1)
      .maybeSingle<{
        blocker_user_id: string;
        blocked_inviter_user_id: string;
      }>(),
  ]);

  if (
    viewerFollowsResult.error ||
    targetFollowsResult.error ||
    sentInvitationResult.error ||
    receivedInvitationResult.error ||
    blockResult.error
  ) {
    return {
      data: null,
      error:
        viewerFollowsResult.error ??
        targetFollowsResult.error ??
        sentInvitationResult.error ??
        receivedInvitationResult.error ??
        blockResult.error ??
        EXCHANGE_DATA_ERROR,
    };
  }

  const viewerFollows = viewerFollowsResult.data;
  const targetFollows = targetFollowsResult.data;
  const sentInvitation = sentInvitationResult.data;
  const receivedInvitation = receivedInvitationResult.data;
  const block = blockResult.data;

  if (
    (viewerFollows &&
      (typeof viewerFollows.follower_id !== "string" ||
        typeof viewerFollows.following_id !== "string" ||
        !isUuid(viewerFollows.follower_id) ||
        !isUuid(viewerFollows.following_id) ||
        viewerFollows.follower_id.toLowerCase() !== viewerId ||
        viewerFollows.following_id.toLowerCase() !== targetId)) ||
    (targetFollows &&
      (typeof targetFollows.follower_id !== "string" ||
        typeof targetFollows.following_id !== "string" ||
        !isUuid(targetFollows.follower_id) ||
        !isUuid(targetFollows.following_id) ||
        targetFollows.follower_id.toLowerCase() !== targetId ||
        targetFollows.following_id.toLowerCase() !== viewerId)) ||
    (sentInvitation &&
      (typeof sentInvitation.id !== "string" ||
        typeof sentInvitation.inviter_user_id !== "string" ||
        typeof sentInvitation.invitee_user_id !== "string" ||
        !isUuid(sentInvitation.id) ||
        !isUuid(sentInvitation.inviter_user_id) ||
        !isUuid(sentInvitation.invitee_user_id) ||
        sentInvitation.inviter_user_id.toLowerCase() !== viewerId ||
        sentInvitation.invitee_user_id.toLowerCase() !== targetId)) ||
    (receivedInvitation &&
      (typeof receivedInvitation.id !== "string" ||
        typeof receivedInvitation.inviter_user_id !== "string" ||
        typeof receivedInvitation.invitee_user_id !== "string" ||
        !isUuid(receivedInvitation.id) ||
        !isUuid(receivedInvitation.inviter_user_id) ||
        !isUuid(receivedInvitation.invitee_user_id) ||
        receivedInvitation.inviter_user_id.toLowerCase() !== targetId ||
        receivedInvitation.invitee_user_id.toLowerCase() !== viewerId)) ||
    (block &&
      (typeof block.blocker_user_id !== "string" ||
        typeof block.blocked_inviter_user_id !== "string" ||
        !isUuid(block.blocker_user_id) ||
        !isUuid(block.blocked_inviter_user_id) ||
        block.blocker_user_id.toLowerCase() !== viewerId ||
        block.blocked_inviter_user_id.toLowerCase() !== targetId)) ||
    (sentInvitation && receivedInvitation)
  ) {
    return { data: null, error: EXCHANGE_DATA_ERROR };
  }

  const data: ExchangeProfileContext = {
    isMutualFollowing: Boolean(viewerFollows && targetFollows),
    pendingDirection: sentInvitation
      ? "sent"
      : receivedInvitation
        ? "received"
        : null,
    isBlockingInvitations: Boolean(block),
  };

  return { data, error: null };
}

export async function getExchangeDiaryDetail(
  supabase: SupabaseClient,
  viewerUserId: string,
  diaryId: string,
) {
  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);

  if (!canonicalDiaryId) {
    return { status: "not-found" as const };
  }

  const diaryResult = await supabase
    .from("exchange_diaries")
    .select(
      "id, title, state, started_at, archived_at, created_at",
    )
    .eq("id", canonicalDiaryId)
    .limit(2)
    .returns<unknown[]>();

  if (diaryResult.error || !diaryResult.data) {
    return { status: "error" as const };
  }

  if (diaryResult.data.length === 0) {
    return { status: "not-found" as const };
  }

  if (diaryResult.data.length !== 1) {
    return { status: "error" as const };
  }

  const diary = parseDiaryRow(diaryResult.data[0]);

  if (!diary || diary.id !== canonicalDiaryId) {
    return { status: "error" as const };
  }

  const participantResult = await hydrateParticipants(supabase, [diary.id]);
  const participants = participantResult.participantsByDiaryId?.get(diary.id);
  const viewerParticipants = participants
    ? getViewerParticipants(participants, viewerUserId)
    : null;

  if (participantResult.error || !participants || !viewerParticipants) {
    return { status: "error" as const };
  }

  const data: ExchangeDiaryDetail = {
    diaryId: diary.id,
    title: diary.title,
    state: diary.state,
    startedAt: diary.started_at,
    createdAt: diary.created_at,
    archivedAt: diary.archived_at,
    participants,
    viewerParticipant: viewerParticipants.viewerParticipant,
    counterpart: viewerParticipants.counterpart,
  };

  return { status: "found" as const, data };
}

async function hydrateEntries(
  supabase: SupabaseClient,
  rows: ParsedEntryRow[],
) {
  const activeEntryIds = rows.flatMap((entry) =>
    entry.kind === "active" ? [entry.entryId] : [],
  );
  const [tagsResult, imagesResult] = await Promise.all([
    activeEntryIds.length > 0
      ? supabase
          .rpc("my_diary_get_exchange_entry_tags", {
            p_entry_ids: activeEntryIds,
          })
          .returns<unknown[]>()
      : Promise.resolve({ data: [] as unknown[], error: null }),
    getExchangeEntryImagesByEntryIds(supabase, activeEntryIds),
  ]);

  if (
    tagsResult.error ||
    imagesResult.error ||
    !tagsResult.data ||
    !imagesResult.data
  ) {
    return {
      data: null,
      error: tagsResult.error ?? imagesResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const rawTagsData: unknown = tagsResult.data;

  if (!Array.isArray(rawTagsData)) {
    return { data: null, error: EXCHANGE_DATA_ERROR };
  }

  const tagsByEntryId = new Map<string, ExchangeEntryTag[]>();
  const tagKeys = new Set<string>();

  for (const value of rawTagsData) {
    const tag = parseTagRow(value);

    if (!tag || !activeEntryIds.includes(tag.entry_id)) {
      return { data: null, error: EXCHANGE_DATA_ERROR };
    }

    const tagKey = `${tag.entry_id}:${tag.tag_id}`;

    if (tagKeys.has(tagKey)) {
      return { data: null, error: EXCHANGE_DATA_ERROR };
    }

    tagKeys.add(tagKey);
    const entryTags = tagsByEntryId.get(tag.entry_id) ?? [];
    entryTags.push({ tagId: tag.tag_id, name: tag.name });
    tagsByEntryId.set(tag.entry_id, entryTags);
  }

  const data: ExchangeEntry[] = rows.map((entry) =>
    entry.kind === "deleted"
      ? entry
      : {
          ...entry,
          tags: tagsByEntryId.get(entry.entryId) ?? [],
          images: imagesResult.data.get(entry.entryId) ?? [],
        },
  );

  return { data, error: null };
}

export async function getEditableExchangeEntry(
  supabase: SupabaseClient,
  diaryId: string,
  entryId: string,
  viewerParticipantId: string,
) {
  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);
  const canonicalEntryId = canonicalizeExchangeUuid(entryId);
  const canonicalViewerParticipantId =
    canonicalizeExchangeUuid(viewerParticipantId);

  if (
    !canonicalDiaryId ||
    !canonicalEntryId ||
    !canonicalViewerParticipantId
  ) {
    return { status: "not-found" as const };
  }

  const entryResult = await supabase
    .from("exchange_entries")
    .select(
      "id, diary_id, author_participant_id, title, body, mood, location_name, created_at, deleted_at",
    )
    .eq("id", canonicalEntryId)
    .eq("diary_id", canonicalDiaryId)
    .eq("author_participant_id", canonicalViewerParticipantId)
    .is("deleted_at", null)
    .limit(2)
    .returns<unknown[]>();

  if (entryResult.error || !entryResult.data) {
    return { status: "error" as const };
  }

  if (entryResult.data.length === 0) {
    return { status: "not-found" as const };
  }

  if (entryResult.data.length !== 1) {
    return { status: "error" as const };
  }

  const parsedEntry = parseEntryRow(entryResult.data[0]);

  if (
    !parsedEntry ||
    parsedEntry.kind !== "active" ||
    parsedEntry.entryId !== canonicalEntryId ||
    parsedEntry.diaryId !== canonicalDiaryId ||
    parsedEntry.authorParticipantId !== canonicalViewerParticipantId
  ) {
    return { status: "error" as const };
  }

  const hydrationResult = await hydrateEntries(supabase, [parsedEntry]);
  const entry = hydrationResult.data?.[0];

  if (
    hydrationResult.error ||
    !entry ||
    entry.kind !== "active" ||
    entry.entryId !== canonicalEntryId
  ) {
    return { status: "error" as const };
  }

  return { status: "found" as const, data: entry };
}

export async function getExchangeEntryPage(
  supabase: SupabaseClient,
  diaryId: string,
  mode: ExchangeEntryMode,
  cursor: ExchangeEntryCursor | null,
) {
  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);

  if (
    !canonicalDiaryId ||
    (mode !== "oldest" && mode !== "latest") ||
    (cursor &&
      (cursor.diaryId !== canonicalDiaryId || cursor.mode !== mode))
  ) {
    return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
  }

  const ascending = mode === "oldest";
  let query = supabase
    .from("exchange_entries")
    .select(
      "id, diary_id, author_participant_id, title, body, mood, location_name, created_at, deleted_at",
    )
    .eq("diary_id", canonicalDiaryId)
    .order("created_at", { ascending })
    .order("id", { ascending })
    .limit(EXCHANGE_PAGE_SIZE + 1);

  if (cursor) {
    const comparison = mode === "oldest" ? "gt" : "lt";
    query = query.or(
      `created_at.${comparison}.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.${comparison}.${cursor.entryId})`,
    );
  }

  const entriesResult = await query.returns<unknown[]>();

  if (entriesResult.error || !entriesResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: entriesResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const entries: ParsedEntryRow[] = [];

  for (const value of entriesResult.data) {
    const entry = parseEntryRow(value);

    if (!entry || entry.diaryId !== canonicalDiaryId) {
      return { data: null, nextCursor: null, error: EXCHANGE_DATA_ERROR };
    }

    entries.push(entry);
  }

  const pageInQueryOrder = entries.slice(0, EXCHANGE_PAGE_SIZE);
  const hydrationResult = await hydrateEntries(supabase, pageInQueryOrder);

  if (hydrationResult.error || !hydrationResult.data) {
    return {
      data: null,
      nextCursor: null,
      error: hydrationResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const cursorEntry = pageInQueryOrder.at(-1);
  const nextCursor =
    entries.length > EXCHANGE_PAGE_SIZE && cursorEntry
      ? encodeExchangeEntryCursor({
          diaryId: canonicalDiaryId,
          mode,
          direction: mode === "oldest" ? "after" : "before",
          createdAt: cursorEntry.createdAt,
          entryId: cursorEntry.entryId,
        })
      : null;
  const data =
    mode === "latest"
      ? [...hydrationResult.data].reverse()
      : hydrationResult.data;

  return { data, nextCursor, error: null };
}

export async function getLatestExchangeEntry(
  supabase: SupabaseClient,
  diaryId: string,
) {
  const canonicalDiaryId = canonicalizeExchangeUuid(diaryId);

  if (!canonicalDiaryId) {
    return { data: null, error: EXCHANGE_DATA_ERROR };
  }

  const result = await supabase
    .from("exchange_entries")
    .select("id, diary_id, author_participant_id, created_at, deleted_at")
    .eq("diary_id", canonicalDiaryId)
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(1)
    .returns<unknown[]>();

  if (result.error || !result.data) {
    return { data: null, error: result.error ?? EXCHANGE_DATA_ERROR };
  }

  const value = result.data[0];

  if (!value) {
    return { data: null, error: null };
  }

  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("diary_id" in value) ||
    !("author_participant_id" in value) ||
    !("created_at" in value) ||
    !("deleted_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.diary_id !== "string" ||
    value.diary_id.toLowerCase() !== canonicalDiaryId ||
    typeof value.author_participant_id !== "string" ||
    !isUuid(value.author_participant_id) ||
    !isTimestamp(value.created_at) ||
    (value.deleted_at !== null && !isTimestamp(value.deleted_at))
  ) {
    return { data: null, error: EXCHANGE_DATA_ERROR };
  }

  const data: LatestExchangeEntry = {
    entryId: value.id.toLowerCase(),
    diaryId: canonicalDiaryId,
    authorParticipantId: value.author_participant_id.toLowerCase(),
    createdAt: value.created_at,
    deleted: value.deleted_at !== null,
  };

  return { data, error: null };
}

function parseInvitationTargetRow(value: unknown): InvitationTargetRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("status" in value) ||
    !("diary_id" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    (value.status !== "pending" &&
      value.status !== "accepted" &&
      value.status !== "rejected" &&
      value.status !== "cancelled" &&
      value.status !== "invalidated") ||
    !isNullableUuid(value.diary_id)
  ) {
    return null;
  }

  if (
    (value.status === "accepted" && value.diary_id === null) ||
    (value.status !== "accepted" && value.diary_id !== null)
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    status: value.status,
    diary_id: value.diary_id?.toLowerCase() ?? null,
  };
}

function parseEntryTargetRow(value: unknown): EntryTargetRow | null {
  if (
    typeof value !== "object" ||
    value === null ||
    !("id" in value) ||
    !("diary_id" in value) ||
    !("deleted_at" in value) ||
    typeof value.id !== "string" ||
    !isUuid(value.id) ||
    typeof value.diary_id !== "string" ||
    !isUuid(value.diary_id) ||
    (value.deleted_at !== null && !isTimestamp(value.deleted_at))
  ) {
    return null;
  }

  return {
    id: value.id.toLowerCase(),
    diary_id: value.diary_id.toLowerCase(),
    deleted_at: value.deleted_at,
  };
}

export async function hydrateExchangeNotificationTargets(
  supabase: SupabaseClient,
  references: ExchangeNotificationTargetReference[],
) {
  const invitationIds = [
    ...new Set(
      references.flatMap((reference) =>
        reference.invitationId ? [reference.invitationId] : [],
      ),
    ),
  ];
  const referencedDiaryIds = [
    ...new Set(
      references.flatMap((reference) =>
        reference.diaryId ? [reference.diaryId] : [],
      ),
    ),
  ];
  const entryIds = [
    ...new Set(
      references.flatMap((reference) =>
        reference.entryId ? [reference.entryId] : [],
      ),
    ),
  ];
  const [invitationsResult, entriesResult] = await Promise.all([
    invitationIds.length > 0
      ? supabase
          .from("exchange_invitations")
          .select("id, status, diary_id")
          .in("id", invitationIds)
          .returns<unknown[]>()
      : Promise.resolve({ data: [] as unknown[], error: null }),
    entryIds.length > 0
      ? supabase
          .from("exchange_entries")
          .select("id, diary_id, deleted_at")
          .in("id", entryIds)
          .returns<unknown[]>()
      : Promise.resolve({ data: [] as unknown[], error: null }),
  ]);

  if (
    invitationsResult.error ||
    entriesResult.error ||
    !invitationsResult.data ||
    !entriesResult.data
  ) {
    return {
      data: null,
      error:
        invitationsResult.error ??
        entriesResult.error ??
        EXCHANGE_DATA_ERROR,
    };
  }

  const invitationsById = new Map<string, InvitationTargetRow>();

  for (const value of invitationsResult.data) {
    const invitation = parseInvitationTargetRow(value);

    if (!invitation || !invitationIds.includes(invitation.id)) {
      return { data: null, error: EXCHANGE_DATA_ERROR };
    }

    invitationsById.set(invitation.id, invitation);
  }

  const diaryIds = [
    ...new Set([
      ...referencedDiaryIds,
      ...[...invitationsById.values()].flatMap((invitation) =>
        invitation.status === "accepted" && invitation.diary_id
          ? [invitation.diary_id]
          : [],
      ),
    ]),
  ];
  const diariesResult =
    diaryIds.length > 0
      ? await supabase
          .from("exchange_diaries")
          .select("id")
          .in("id", diaryIds)
          .returns<unknown[]>()
      : { data: [] as unknown[], error: null };

  if (diariesResult.error || !diariesResult.data) {
    return {
      data: null,
      error: diariesResult.error ?? EXCHANGE_DATA_ERROR,
    };
  }

  const availableDiaryIds = new Set<string>();

  for (const value of diariesResult.data) {
    if (
      typeof value !== "object" ||
      value === null ||
      !("id" in value) ||
      typeof value.id !== "string" ||
      !isUuid(value.id)
    ) {
      return { data: null, error: EXCHANGE_DATA_ERROR };
    }

    const diaryId = value.id.toLowerCase();

    if (!diaryIds.includes(diaryId)) {
      return { data: null, error: EXCHANGE_DATA_ERROR };
    }

    availableDiaryIds.add(diaryId);
  }

  const entriesById = new Map<string, EntryTargetRow>();

  for (const value of entriesResult.data) {
    const entry = parseEntryTargetRow(value);

    if (!entry || !entryIds.includes(entry.id)) {
      return { data: null, error: EXCHANGE_DATA_ERROR };
    }

    entriesById.set(entry.id, entry);
  }

  const data = new Map<string, ExchangeNotificationTarget>();

  for (const reference of references) {
    if (reference.notificationType === "exchange_invitation") {
      const invitation = invitationsById.get(reference.invitationId);

      if (!invitation) {
        data.set(reference.notificationId, {
          kind: "unavailable",
          futureTargetAvailable: false,
        });
      } else if (invitation.status === "pending") {
        data.set(reference.notificationId, {
          kind: "invitation",
          state: "pending",
          futureTargetAvailable: true,
        });
      } else if (invitation.status === "accepted" && invitation.diary_id) {
        data.set(reference.notificationId, {
          kind: "invitation",
          state: "accepted",
          diaryId: invitation.diary_id,
          futureTargetAvailable: availableDiaryIds.has(invitation.diary_id),
        });
      } else {
        data.set(reference.notificationId, {
          kind: "invitation",
          state: "terminal",
          futureTargetAvailable: false,
        });
      }
    } else if (
      reference.notificationType === "exchange_invitation_accepted"
    ) {
      data.set(reference.notificationId, {
        kind: "diary",
        diaryId: reference.diaryId,
        futureTargetAvailable: availableDiaryIds.has(reference.diaryId),
      });
    } else {
      const entry = entriesById.get(reference.entryId);
      const entryState = !entry
        ? "unavailable"
        : entry.deleted_at
          ? "deleted"
          : "active";

      if (entry && entry.diary_id !== reference.diaryId) {
        return { data: null, error: EXCHANGE_DATA_ERROR };
      }

      data.set(reference.notificationId, {
        kind: "entry",
        diaryId: reference.diaryId,
        entryId: reference.entryId,
        entryState,
        futureTargetAvailable: availableDiaryIds.has(reference.diaryId),
      });
    }
  }

  return { data, error: null };
}
