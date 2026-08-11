import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createClient } from "@supabase/supabase-js";

const apiUrl = process.env.E2G_LOCAL_SUPABASE_URL;
const publishableKey = process.env.E2G_LOCAL_SUPABASE_PUBLISHABLE_KEY;
const databaseContainer = "supabase_db_my-diary";

if (!apiUrl || !publishableKey) {
  throw new Error("Local Supabase URL and publishable key are required.");
}

const parsedUrl = new URL(apiUrl);
if (
  parsedUrl.protocol !== "http:" ||
  !["127.0.0.1", "localhost"].includes(parsedUrl.hostname) ||
  parsedUrl.port !== "54321"
) {
  throw new Error("E2g verification refuses every non-local Supabase URL.");
}

const bucket = "exchange-entry-images";
const png = Uint8Array.from(
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
    "base64",
  ),
);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function assertUuid(value) {
  assert(
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
      value,
    ),
    "Expected a UUID fixture identifier.",
  );
  return value;
}

function localSql(sql) {
  return execFileSync(
    "docker",
    [
      "exec",
      "-i",
      databaseContainer,
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
      "-At",
    ],
    { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
  ).trim();
}

function newClient() {
  return createClient(apiUrl, publishableKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

async function signUp(label) {
  const client = newClient();
  const password = `E2g-${randomUUID()}-Aa1!`;
  const email = `e2g-${label}-${randomUUID()}@example.test`;
  const { data, error } = await client.auth.signUp({ email, password });
  assert(!error, `${label} local sign-up failed.`);
  assert(data.user && data.session, `${label} did not receive a local session.`);
  assertUuid(data.user.id);
  return { client, userId: data.user.id, token: data.session.access_token };
}

async function upload(client, path) {
  const { error } = await client.storage.from(bucket).upload(path, png, {
    contentType: "image/png",
    upsert: false,
  });
  assert(!error, "Local Storage upload failed.");
}

function normalizeJsonBody(body) {
  if (Array.isArray(body)) {
    return {
      kind: "array",
      dataCount: body.length,
      returnedNames: body.map((item) => item?.name ?? null),
      error: null,
    };
  }
  return {
    kind: "object",
    dataCount: null,
    returnedNames: [],
    error: body
      ? {
          statusCode: body.statusCode ?? body.status ?? null,
          error: body.error ?? body.code ?? null,
          message: body.message ?? null,
        }
      : null,
  };
}

async function rawDelete(token, paths) {
  const started = performance.now();
  const response = await fetch(`${apiUrl}/storage/v1/object/${bucket}`, {
    method: "DELETE",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ prefixes: paths }),
  });
  const bodyText = await response.text();
  let body = null;
  try {
    body = bodyText ? JSON.parse(bodyText) : null;
  } catch {
    body = null;
  }
  return {
    status: response.status,
    statusText: response.statusText,
    contentType: response.headers.get("content-type"),
    durationMs: Number((performance.now() - started).toFixed(2)),
    ...normalizeJsonBody(body),
  };
}

async function rawDownload(token, path) {
  const response = await fetch(
    `${apiUrl}/storage/v1/object/authenticated/${bucket}/${path}`,
    {
      headers: {
        apikey: publishableKey,
        authorization: `Bearer ${token}`,
      },
    },
  );
  const contentType = response.headers.get("content-type");
  let error = null;
  if (!response.ok) {
    const bodyText = await response.text();
    try {
      const body = bodyText ? JSON.parse(bodyText) : null;
      error = normalizeJsonBody(body).error;
    } catch {
      error = { statusCode: null, error: null, message: null };
    }
  } else {
    await response.arrayBuffer();
  }
  return { status: response.status, contentType, error };
}

async function rawList(token, prefix, search) {
  const response = await fetch(`${apiUrl}/storage/v1/object/list/${bucket}`, {
    method: "POST",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      prefix,
      limit: 10,
      offset: 0,
      search,
      sortBy: { column: "name", order: "asc" },
    }),
  });
  const body = await response.json();
  return { status: response.status, ...normalizeJsonBody(body) };
}

function responseFingerprint(response) {
  return JSON.stringify({
    status: response.status,
    statusText: response.statusText ?? null,
    kind: response.kind ?? null,
    dataCount: response.dataCount ?? null,
    error: response.error ?? null,
  });
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const midpoint = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[midpoint]
    : Number(((sorted[midpoint - 1] + sorted[midpoint]) / 2).toFixed(2));
}

const author = await signUp("author");
const reporter = await signUp("reporter");
const admin = await signUp("admin");

const diaryId = randomUUID();
const authorParticipantId = randomUUID();
const reporterParticipantId = randomUUID();
const heldEntryId = randomUUID();
const unheldEntryId = randomUUID();
const suspendedEntryId = randomUUID();
const orphanEntryId = randomUUID();
const heldImageId = randomUUID();
const unheldImageId = randomUUID();
const suspendedImageId = randomUUID();
const orphanImageId = randomUUID();

[
  diaryId,
  authorParticipantId,
  reporterParticipantId,
  heldEntryId,
  unheldEntryId,
  suspendedEntryId,
  orphanEntryId,
  heldImageId,
  unheldImageId,
  suspendedImageId,
  orphanImageId,
].forEach(assertUuid);

const heldPath = `${author.userId}/${diaryId}/${heldEntryId}/${heldImageId}`;
const unheldPath = `${author.userId}/${diaryId}/${unheldEntryId}/${unheldImageId}`;
const suspendedPath = `${author.userId}/${diaryId}/${suspendedEntryId}/${suspendedImageId}`;
const orphanPath = `${author.userId}/${diaryId}/${orphanEntryId}/${orphanImageId}`;

localSql(`
  begin;
  update public.accounts set role = 'admin'
  where user_id = ${sqlLiteral(admin.userId)}::uuid;

  insert into public.exchange_diaries
    (id, state, created_by_position, archived_at, archive_cause)
  values (${sqlLiteral(diaryId)}::uuid, 'active', 1, null, null);

  insert into public.exchange_diary_participants
    (id, diary_id, position, user_id)
  values
    (${sqlLiteral(reporterParticipantId)}::uuid,
     ${sqlLiteral(diaryId)}::uuid, 1,
     ${sqlLiteral(reporter.userId)}::uuid),
    (${sqlLiteral(authorParticipantId)}::uuid,
     ${sqlLiteral(diaryId)}::uuid, 2,
     ${sqlLiteral(author.userId)}::uuid);

  insert into public.exchange_entries
    (id, diary_id, author_participant_id, title, body)
  values
    (${sqlLiteral(heldEntryId)}::uuid, ${sqlLiteral(diaryId)}::uuid,
     ${sqlLiteral(authorParticipantId)}::uuid, 'held', 'held body'),
    (${sqlLiteral(unheldEntryId)}::uuid, ${sqlLiteral(diaryId)}::uuid,
     ${sqlLiteral(authorParticipantId)}::uuid, 'unheld', 'unheld body'),
    (${sqlLiteral(suspendedEntryId)}::uuid, ${sqlLiteral(diaryId)}::uuid,
     ${sqlLiteral(authorParticipantId)}::uuid, 'suspended', 'suspended body');
  commit;
`);

await upload(author.client, heldPath);
await upload(author.client, unheldPath);
await upload(author.client, suspendedPath);
await upload(author.client, orphanPath);

localSql(`
  insert into public.exchange_entry_images
    (id, entry_id, storage_path, sort_order)
  values
    (${sqlLiteral(heldImageId)}::uuid, ${sqlLiteral(heldEntryId)}::uuid,
     ${sqlLiteral(heldPath)}, 0),
    (${sqlLiteral(unheldImageId)}::uuid, ${sqlLiteral(unheldEntryId)}::uuid,
     ${sqlLiteral(unheldPath)}, 0),
    (${sqlLiteral(suspendedImageId)}::uuid,
     ${sqlLiteral(suspendedEntryId)}::uuid,
     ${sqlLiteral(suspendedPath)}, 0);
`);

const { data: reportId, error: reportError } = await reporter.client.rpc(
  "my_diary_create_exchange_entry_report",
  { p_entry_id: heldEntryId, p_reason: "harassment", p_details: null },
);
assert(!reportError && reportId, "Creating local report evidence failed.");
assertUuid(reportId);

for (const [entryId, title] of [
  [heldEntryId, "held edited"],
  [unheldEntryId, "unheld edited"],
  [suspendedEntryId, "suspended edited"],
]) {
  const { data, error } = await author.client.rpc(
    "my_diary_update_exchange_entry_with_images",
    {
      p_entry_id: entryId,
      p_title: title,
      p_body: `${title} body`,
      p_mood: null,
      p_location_name: null,
      p_tags: null,
      p_image_manifest: [],
    },
  );
  assert(!error, "Removing confirmed local image relation failed.");
  assert(
    JSON.stringify(Object.keys(data).sort()) === JSON.stringify(["entryId"]),
    "Exchange update leaked a cleanup-path contract.",
  );
}

const beforeDueUnheld = await rawDelete(admin.token, [unheldPath]);
const beforeDueHeld = await rawDelete(admin.token, [heldPath]);
assert(
  beforeDueUnheld.dataCount === 0 && beforeDueHeld.dataCount === 0,
  "Admin maintenance deleted a candidate before its deadline.",
);

const heldRetention = await rawDelete(author.token, [heldPath]);
const unheldRetention = await rawDelete(author.token, [unheldPath]);
assert(
  responseFingerprint(heldRetention) === responseFingerprint(unheldRetention),
  "Held and unheld candidates have different owner DELETE responses.",
);
assert(
  localSql(`select count(*) from storage.objects where name in (
    ${sqlLiteral(heldPath)}, ${sqlLiteral(unheldPath)}
  );`) === "2",
  "Owner DELETE changed retained candidate objects.",
);

const timingHeld = [];
const timingUnheld = [];
for (let index = 0; index < 10; index += 1) {
  timingHeld.push((await rawDelete(author.token, [heldPath])).durationMs);
  timingUnheld.push((await rawDelete(author.token, [unheldPath])).durationMs);
}

const orphanDelete = await rawDelete(author.token, [orphanPath]);
assert(
  orphanDelete.status === 200 && orphanDelete.dataCount === 1,
  "Never-confirmed owner orphan cleanup regressed.",
);

localSql(`
  update my_diary_private.exchange_entry_image_cleanup_candidates
  set removed_at = statement_timestamp() - interval '8 days',
      delete_after = statement_timestamp() - interval '1 day'
  where storage_path in (
    ${sqlLiteral(heldPath)},
    ${sqlLiteral(unheldPath)},
    ${sqlLiteral(suspendedPath)}
  );
`);

const dueHeldOwner = await rawDelete(author.token, [heldPath]);
const dueUnheldOwner = await rawDelete(author.token, [unheldPath]);
assert(
  responseFingerprint(dueHeldOwner) === responseFingerprint(dueUnheldOwner),
  "Seven days reopened an evidence-dependent owner DELETE response.",
);

const adminEvidenceDownload = await rawDownload(admin.token, heldPath);
const adminNonEvidenceDownload = await rawDownload(admin.token, unheldPath);
assert(
  adminEvidenceDownload.status === 200 &&
    adminNonEvidenceDownload.status !== 200,
  "Admin exact-evidence Storage SELECT boundary differs.",
);

localSql(`update public.accounts set status = 'suspended'
  where user_id = ${sqlLiteral(admin.userId)}::uuid;`);
const suspendedAdminDelete = await rawDelete(admin.token, [suspendedPath]);
assert(
  suspendedAdminDelete.dataCount === 0 &&
    localSql(`select count(*) from storage.objects
      where name = ${sqlLiteral(suspendedPath)};`) === "1",
  "Suspended admin crossed the maintenance boundary.",
);
localSql(`update public.accounts set status = 'active'
  where user_id = ${sqlLiteral(admin.userId)}::uuid;`);

const maintenanceUnheld = await rawDelete(admin.token, [unheldPath]);
const maintenanceHeld = await rawDelete(admin.token, [heldPath]);
assert(
  maintenanceUnheld.status === 200 && maintenanceUnheld.dataCount === 1,
  "Active-admin maintenance did not delete the due unheld candidate.",
);
assert(
  maintenanceHeld.status === 200 && maintenanceHeld.dataCount === 0,
  "Active-admin maintenance deleted retained report evidence.",
);

const { data: completed, error: completeError } = await admin.client.rpc(
  "my_diary_complete_exchange_image_cleanup",
  { p_storage_path: unheldPath },
);
assert(!completeError && completed === true, "Candidate completion failed.");

const retryMissing = await rawDelete(author.token, [unheldPath]);
const retryHeld = await rawDelete(author.token, [heldPath]);
assert(
  responseFingerprint(retryMissing) === responseFingerprint(retryHeld),
  "Known-path retry distinguishes missing from retained evidence.",
);

const downloadMissing = await rawDownload(author.token, unheldPath);
const downloadHeld = await rawDownload(author.token, heldPath);
assert(
  responseFingerprint(downloadMissing) === responseFingerprint(downloadHeld),
  "Owner download distinguishes missing from RLS-hidden evidence.",
);

const unheldParts = unheldPath.split("/");
const heldParts = heldPath.split("/");
const listMissing = await rawList(
  author.token,
  unheldParts.slice(0, 3).join("/"),
  unheldParts[3],
);
const listHeld = await rawList(
  author.token,
  heldParts.slice(0, 3).join("/"),
  heldParts[3],
);
assert(
  responseFingerprint(listMissing) === responseFingerprint(listHeld),
  "Owner list distinguishes missing from RLS-hidden evidence.",
);

const mixedDelete = await rawDelete(author.token, [heldPath, unheldPath]);
assert(
  mixedDelete.status === retryHeld.status && mixedDelete.dataCount === 0,
  "Mixed known-path DELETE exposed candidate cardinality.",
);

const { error: resolveError } = await admin.client.rpc(
  "my_diary_update_report_status",
  { p_report_id: reportId, p_status: "resolved" },
);
assert(!resolveError, "Resolving local report failed.");
localSql(`
  alter table public.reports
    disable trigger my_diary_reports_reject_status_transition;
  update public.reports
  set resolved_at = statement_timestamp() - interval '31 days',
      evidence_delete_after = statement_timestamp() - interval '1 day'
  where id = ${sqlLiteral(reportId)}::uuid;
  alter table public.reports
    enable trigger my_diary_reports_reject_status_transition;
`);
const { data: purged, error: purgeError } = await admin.client.rpc(
  "my_diary_purge_expired_report_evidence",
  { p_report_id: reportId },
);
assert(!purgeError && purged === true, "Purging terminal evidence failed.");
const maintenanceHeldAfterPurge = await rawDelete(admin.token, [heldPath]);
assert(
  maintenanceHeldAfterPurge.status === 200 &&
    maintenanceHeldAfterPurge.dataCount === 1,
  "Last evidence purge did not release trusted physical cleanup.",
);
const { error: heldCompleteError } = await admin.client.rpc(
  "my_diary_complete_exchange_image_cleanup",
  { p_storage_path: heldPath },
);
assert(!heldCompleteError, "Held candidate completion failed after purge.");

const summary = {
  orphan: {
    status: orphanDelete.status,
    dataCount: orphanDelete.dataCount,
    error: orphanDelete.error,
  },
  candidateRetention: {
    held: {
      status: heldRetention.status,
      dataCount: heldRetention.dataCount,
      error: heldRetention.error,
    },
    unheld: {
      status: unheldRetention.status,
      dataCount: unheldRetention.dataCount,
      error: unheldRetention.error,
    },
  },
  maintenance: {
    beforeDueUnheld: {
      status: beforeDueUnheld.status,
      dataCount: beforeDueUnheld.dataCount,
    },
    dueUnheld: {
      status: maintenanceUnheld.status,
      dataCount: maintenanceUnheld.dataCount,
    },
    dueHeld: {
      status: maintenanceHeld.status,
      dataCount: maintenanceHeld.dataCount,
    },
    suspendedAdmin: {
      status: suspendedAdminDelete.status,
      dataCount: suspendedAdminDelete.dataCount,
    },
  },
  retry: {
    missing: {
      status: retryMissing.status,
      dataCount: retryMissing.dataCount,
      error: retryMissing.error,
    },
    retainedEvidence: {
      status: retryHeld.status,
      dataCount: retryHeld.dataCount,
      error: retryHeld.error,
    },
  },
  download: {
    missing: downloadMissing,
    retainedEvidence: downloadHeld,
    activeAdminEvidenceStatus: adminEvidenceDownload.status,
    activeAdminNonEvidenceStatus: adminNonEvidenceDownload.status,
  },
  list: {
    missing: { status: listMissing.status, dataCount: listMissing.dataCount },
    retainedEvidence: {
      status: listHeld.status,
      dataCount: listHeld.dataCount,
    },
  },
  timingMs: {
    heldMedian: median(timingHeld),
    heldRange: [Math.min(...timingHeld), Math.max(...timingHeld)],
    unheldMedian: median(timingUnheld),
    unheldRange: [Math.min(...timingUnheld), Math.max(...timingUnheld)],
  },
};

console.log(JSON.stringify(summary, null, 2));
