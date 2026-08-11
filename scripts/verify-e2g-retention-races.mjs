import { execFileSync, spawn } from "node:child_process";
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
  throw new Error("Race verification refuses every non-local Supabase URL.");
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

function quote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
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

function client() {
  return createClient(apiUrl, publishableKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

async function signUp(label) {
  const instance = client();
  const { data, error } = await instance.auth.signUp({
    email: `e2g-race-${label}-${randomUUID()}@example.test`,
    password: `E2g-${randomUUID()}-Aa1!`,
  });
  assert(!error && data.user && data.session, `${label} sign-up failed.`);
  return {
    client: instance,
    userId: data.user.id,
    token: data.session.access_token,
  };
}

async function rawDelete(token, path) {
  const response = await fetch(`${apiUrl}/storage/v1/object/${bucket}`, {
    method: "DELETE",
    headers: {
      apikey: publishableKey,
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ prefixes: [path] }),
  });
  const body = await response.json();
  return { status: response.status, dataCount: Array.isArray(body) ? body.length : null };
}

async function delay(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function lockEntry(entryId, milliseconds = 1600) {
  const seconds = (milliseconds / 1000).toFixed(3);
  const sql = `begin; select id from public.exchange_entries where id = ${quote(entryId)}::uuid for update; select 'LOCKED'; select pg_sleep(${seconds}); commit;`;
  const child = spawn(
    "docker",
    [
      "exec",
      databaseContainer,
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-v",
      "ON_ERROR_STOP=1",
      "-At",
      "-c",
      sql,
    ],
    { stdio: ["ignore", "pipe", "pipe"] },
  );

  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  const locked = new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error("Timed out waiting for local entry lock.")),
      5000,
    );
    const check = setInterval(() => {
      if (stdout.includes("LOCKED")) {
        clearInterval(check);
        clearTimeout(timeout);
        resolve();
      }
    }, 20);
  });

  const done = new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`Local lock process failed: ${stderr.trim()}`));
    });
  });

  await locked;
  return { done };
}

const author = await signUp("author");
const reporter = await signUp("reporter");
const admin = await signUp("admin");

const diaryId = randomUUID();
const reporterParticipantId = randomUUID();
const authorParticipantId = randomUUID();

localSql(`
  begin;
  update public.accounts set role = 'admin'
  where user_id = ${quote(admin.userId)}::uuid;
  insert into public.exchange_diaries
    (id, state, created_by_position, archived_at, archive_cause)
  values (${quote(diaryId)}::uuid, 'active', 1, null, null);
  insert into public.exchange_diary_participants
    (id, diary_id, position, user_id)
  values
    (${quote(reporterParticipantId)}::uuid, ${quote(diaryId)}::uuid, 1,
     ${quote(reporter.userId)}::uuid),
    (${quote(authorParticipantId)}::uuid, ${quote(diaryId)}::uuid, 2,
     ${quote(author.userId)}::uuid);
  commit;
`);

async function createImageEntry(label) {
  const entryId = randomUUID();
  const imageId = randomUUID();
  const path = `${author.userId}/${diaryId}/${entryId}/${imageId}`;
  localSql(`insert into public.exchange_entries
    (id, diary_id, author_participant_id, title, body)
    values (${quote(entryId)}::uuid, ${quote(diaryId)}::uuid,
      ${quote(authorParticipantId)}::uuid, ${quote(label)}, ${quote(`${label} body`)});`);
  const { error } = await author.client.storage.from(bucket).upload(path, png, {
    contentType: "image/png",
    upsert: false,
  });
  assert(!error, `${label} upload failed.`);
  localSql(`insert into public.exchange_entry_images
    (id, entry_id, storage_path, sort_order)
    values (${quote(imageId)}::uuid, ${quote(entryId)}::uuid,
      ${quote(path)}, 0);`);
  return { entryId, imageId, path };
}

async function reportEntry(entryId) {
  const startedAt = performance.now();
  const result = await reporter.client.rpc(
    "my_diary_create_exchange_entry_report",
    { p_entry_id: entryId, p_reason: "harassment", p_details: null },
  );
  const endedAt = performance.now();
  assert(!result.error && result.data, "Concurrent report RPC failed.");
  return { reportId: result.data, startedAt, endedAt };
}

async function editEntry(entryId, label) {
  const startedAt = performance.now();
  const result = await author.client.rpc(
    "my_diary_update_exchange_entry_with_images",
    {
      p_entry_id: entryId,
      p_title: `${label} edited`,
      p_body: `${label} edited body`,
      p_mood: null,
      p_location_name: null,
      p_tags: null,
      p_image_manifest: [],
    },
  );
  const endedAt = performance.now();
  assert(!result.error, "Concurrent edit RPC failed.");
  return { startedAt, endedAt };
}

async function orderedReportEditRace(order) {
  const fixture = await createImageEntry(order);
  const { done: blockerDone } = await lockEntry(fixture.entryId);
  const first = order === "report-first"
    ? reportEntry(fixture.entryId)
    : editEntry(fixture.entryId, order);
  await delay(120);
  const second = order === "report-first"
    ? editEntry(fixture.entryId, order)
    : reportEntry(fixture.entryId);
  const [firstResult, secondResult] = await Promise.all([first, second]);
  await blockerDone;
  const report = order === "report-first" ? firstResult : secondResult;
  const edit = order === "report-first" ? secondResult : firstResult;
  const imageSnapshots = Number(
    localSql(`select count(*) from public.report_snapshot_images
      where report_id = ${quote(report.reportId)}::uuid
        and storage_path = ${quote(fixture.path)};`),
  );
  const state = localSql(`select
    (select count(*) from public.exchange_entry_images where id = ${quote(fixture.imageId)}::uuid),
    (select count(*) from my_diary_private.exchange_entry_image_cleanup_candidates where image_id = ${quote(fixture.imageId)}::uuid),
    (select count(*) from storage.objects where bucket_id = ${quote(bucket)} and name = ${quote(fixture.path)});`);
  assert(
    state === "0|1|1",
    `${order} violated atomic metadata/candidate/object state.`,
  );
  assert(
    order === "report-first" ? imageSnapshots === 1 : imageSnapshots === 0,
    `${order} produced the wrong serialized snapshot manifest.`,
  );
  assert(
    order === "report-first"
      ? report.endedAt <= edit.endedAt
      : edit.endedAt <= report.endedAt,
    `${order} did not observe the intended lock queue order.`,
  );
  return { ...fixture, report, edit, imageSnapshots };
}

const reportFirst = await orderedReportEditRace("report-first");
const editFirst = await orderedReportEditRace("edit-first");

localSql(`update my_diary_private.exchange_entry_image_cleanup_candidates
  set removed_at = statement_timestamp() - interval '8 days',
      delete_after = statement_timestamp() - interval '1 day'
  where storage_path in (${quote(reportFirst.path)}, ${quote(editFirst.path)});`);

const reportFirstMaintenance = await rawDelete(admin.token, reportFirst.path);
const editFirstMaintenance = await rawDelete(admin.token, editFirst.path);
assert(
  reportFirstMaintenance.dataCount === 0 && editFirstMaintenance.dataCount === 1,
  "Serialized report/edit order did not govern trusted maintenance safely.",
);

// A live source relation cannot be removed by maintenance while reporting.
const liveRace = await createImageEntry("live-report-maintenance");
const [liveReport, liveDelete] = await Promise.all([
  reportEntry(liveRace.entryId),
  rawDelete(admin.token, liveRace.path),
]);
assert(liveDelete.dataCount === 0, "Maintenance deleted a live source image.");
assert(
  localSql(`select
    (select count(*) from public.report_snapshot_images
      where report_id = ${quote(liveReport.reportId)}::uuid
        and storage_path = ${quote(liveRace.path)}),
    (select count(*) from storage.objects
      where bucket_id = ${quote(bucket)} and name = ${quote(liveRace.path)});`) ===
    "1|1",
  "Concurrent report/maintenance lost capturable evidence bytes.",
);

// Purge and maintenance use separate HTTP transactions. Either maintenance
// sees the old evidence and declines, or it waits for purge then deletes; an
// evidence row with missing bytes is never an allowed final state.
const { error: resolveError } = await admin.client.rpc(
  "my_diary_update_report_status",
  { p_report_id: reportFirst.report.reportId, p_status: "resolved" },
);
assert(!resolveError, "Race report resolution failed.");
localSql(`
  alter table public.reports
    disable trigger my_diary_reports_reject_status_transition;
  update public.reports
  set resolved_at = statement_timestamp() - interval '31 days',
      evidence_delete_after = statement_timestamp() - interval '1 day'
  where id = ${quote(reportFirst.report.reportId)}::uuid;
  alter table public.reports
    enable trigger my_diary_reports_reject_status_transition;
`);

const [purgeResult, concurrentMaintenance] = await Promise.all([
  admin.client.rpc("my_diary_purge_expired_report_evidence", {
    p_report_id: reportFirst.report.reportId,
  }),
  rawDelete(admin.token, reportFirst.path),
]);
assert(!purgeResult.error && purgeResult.data === true, "Concurrent purge failed.");
let purgeRaceState = localSql(`select
  (select count(*) from public.report_snapshot_images
    where report_id = ${quote(reportFirst.report.reportId)}::uuid),
  (select count(*) from storage.objects
    where bucket_id = ${quote(bucket)} and name = ${quote(reportFirst.path)});`);
assert(
  purgeRaceState === "0|0" || purgeRaceState === "0|1",
  "Purge/maintenance produced evidence metadata without bytes.",
);
if (purgeRaceState === "0|1") {
  const retry = await rawDelete(admin.token, reportFirst.path);
  assert(retry.dataCount === 1, "Post-purge maintenance retry did not delete bytes.");
  purgeRaceState = "0|0";
}

console.log(
  JSON.stringify(
    {
      reportVsEdit: {
        reportFirst: {
          imageSnapshotCount: reportFirst.imageSnapshots,
          completionOrder: "report-then-edit",
          finalState: "metadata=0,candidate=1,object=1",
        },
        editFirst: {
          imageSnapshotCount: editFirst.imageSnapshots,
          completionOrder: "edit-then-report",
          finalState: "metadata=0,candidate=1,object=1",
        },
      },
      reportVsMaintenance: {
        deleteCount: liveDelete.dataCount,
        finalState: "snapshot=1,object=1",
      },
      purgeVsMaintenance: {
        concurrentDeleteCount: concurrentMaintenance.dataCount,
        finalState: purgeRaceState,
      },
    },
    null,
    2,
  ),
);
