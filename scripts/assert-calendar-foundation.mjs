import assert from "node:assert/strict";

import {
  buildCalendarHref,
  buildCalendarPostIndex,
  formatInstantToCalendarDate,
  getCalendarMonthForInstant,
  getCalendarMonthGrid,
  getCalendarMonthUtcRange,
  getCalendarPostsForDate,
  isCalendarDateInMonth,
  parseCalendarDate,
  parseCalendarMonth,
  shiftCalendarMonth,
} from "../src/lib/calendar.ts";
import { queryCalendarPosts } from "../src/lib/calendar-query.ts";

const validMonths = ["2026-08", "2026-01", "2026-12"];
const invalidMonths = [
  "2026-00",
  "2026-13",
  "2026-8",
  "26-08",
  "202608",
  "abc",
  "",
  "0000-01",
  " 2026-08",
  "2026-08 ",
  "2026-08x",
  ["2026-08", "2026-09"],
];

for (const month of validMonths) {
  assert.equal(parseCalendarMonth(month), month);
}

for (const month of invalidMonths) {
  assert.equal(parseCalendarMonth(month), null);
}

for (const date of ["2026-08-09", "2024-02-29"]) {
  assert.equal(parseCalendarDate(date), date);
}

for (const date of [
  "2025-02-29",
  "2026-02-30",
  "2026-13-01",
  "2026-08-00",
  "2026-8-09",
  "",
  ["2026-08-09", "2026-08-10"],
]) {
  assert.equal(parseCalendarDate(date), null);
}

const august = parseCalendarMonth("2026-08");
const augustNinth = parseCalendarDate("2026-08-09");
const julyLast = parseCalendarDate("2026-07-31");
assert.ok(august && augustNinth && julyLast);
assert.equal(isCalendarDateInMonth(augustNinth, august), true);
assert.equal(isCalendarDateInMonth(julyLast, august), false);

assert.equal(shiftCalendarMonth(august, -1), "2026-07");
assert.equal(shiftCalendarMonth(august, 1), "2026-09");
assert.equal(
  shiftCalendarMonth(parseCalendarMonth("2026-01"), -1),
  "2025-12",
);
assert.equal(
  shiftCalendarMonth(parseCalendarMonth("2026-12"), 1),
  "2027-01",
);

const augustGrid = getCalendarMonthGrid(august);
assert.ok(augustGrid);
assert.equal(augustGrid.length, 6);
assert.deepEqual(augustGrid[0], [
  null,
  null,
  null,
  null,
  null,
  null,
  "2026-08-01",
]);
assert.equal(augustGrid.flat().filter(Boolean).length, 31);
assert.equal(augustGrid.flat().indexOf("2026-08-09"), 14);
assert.equal(buildCalendarHref(august), "/calendar?month=2026-08");
assert.equal(
  buildCalendarHref(august, augustNinth),
  "/calendar?month=2026-08&date=2026-08-09",
);
assert.throws(() => buildCalendarHref(august, julyLast), RangeError);

const leapFebruary = parseCalendarMonth("2024-02");
assert.ok(leapFebruary);
const leapFebruaryGrid = getCalendarMonthGrid(leapFebruary);
assert.ok(leapFebruaryGrid);
assert.equal(leapFebruaryGrid.flat().filter(Boolean).length, 29);
assert.equal(leapFebruaryGrid[0][4], "2024-02-01");

assert.deepEqual(getCalendarMonthUtcRange(august, "Asia/Tokyo"), {
  start: "2026-07-31T15:00:00.000Z",
  end: "2026-08-31T15:00:00.000Z",
});

const march = parseCalendarMonth("2026-03");
assert.ok(march);
assert.deepEqual(getCalendarMonthUtcRange(march, "America/New_York"), {
  start: "2026-03-01T05:00:00.000Z",
  end: "2026-04-01T04:00:00.000Z",
});
assert.deepEqual(getCalendarMonthUtcRange(march, "Europe/London"), {
  start: "2026-03-01T00:00:00.000Z",
  end: "2026-03-31T23:00:00.000Z",
});

const sharedInstant = "2026-08-01T00:30:00Z";
assert.equal(
  formatInstantToCalendarDate(sharedInstant, "Asia/Tokyo"),
  "2026-08-01",
);
assert.equal(
  formatInstantToCalendarDate(sharedInstant, "America/New_York"),
  "2026-07-31",
);
assert.equal(
  getCalendarMonthForInstant(sharedInstant, "America/New_York"),
  "2026-07",
);

const index = buildCalendarPostIndex(
  [
    {
      id: "00000000-0000-4000-8000-000000000001",
      title: "older",
      body: "older body",
      mood: "sad",
      visibility: "private",
      created_at: "2026-08-09T01:00:00.000000+00:00",
    },
    {
      id: "00000000-0000-4000-8000-000000000003",
      title: "latest stable id",
      body: "latest body",
      mood: "happy",
      visibility: "public",
      created_at: "2026-08-09T02:00:00.000000+00:00",
    },
    {
      id: "00000000-0000-4000-8000-000000000002",
      title: "same instant lower id",
      body: "same instant body",
      mood: "calm",
      visibility: "followers",
      created_at: "2026-08-09T02:00:00.000000+00:00",
    },
  ],
  august,
  "Asia/Tokyo",
);

assert.ok(index);
assert.deepEqual(
  index.posts.map((post) => post.id),
  [
    "00000000-0000-4000-8000-000000000003",
    "00000000-0000-4000-8000-000000000002",
    "00000000-0000-4000-8000-000000000001",
  ],
);
assert.deepEqual(index.daySummaries, [
  {
    date: "2026-08-09",
    hasPosts: true,
    postCount: 3,
    mood: "happy",
  },
]);
assert.equal(
  getCalendarPostsForDate(index, august, "2026-08-09")?.length,
  3,
);
assert.deepEqual(
  getCalendarPostsForDate(index, august, "2026-08-10"),
  [],
);
assert.equal(
  getCalendarPostsForDate(index, august, "2026-07-31"),
  null,
);

const queryCalls = [];
const queryBuilder = {
  select(value) {
    queryCalls.push(["select", value]);
    return this;
  },
  eq(column, value) {
    queryCalls.push(["eq", column, value]);
    return this;
  },
  gte(column, value) {
    queryCalls.push(["gte", column, value]);
    return this;
  },
  lt(column, value) {
    queryCalls.push(["lt", column, value]);
    return this;
  },
  is(column, value) {
    queryCalls.push(["is", column, value]);
    return this;
  },
  order(column, options) {
    queryCalls.push(["order", column, options]);
    return this;
  },
  async returns() {
    queryCalls.push(["returns"]);
    return { data: [], error: null };
  },
};
const fakeSupabase = {
  from(table) {
    queryCalls.push(["from", table]);
    return queryBuilder;
  },
};
const tokyoRange = getCalendarMonthUtcRange(august, "Asia/Tokyo");
await queryCalendarPosts(
  fakeSupabase,
  "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  tokyoRange,
);
assert.deepEqual(queryCalls, [
  ["from", "posts"],
  ["select", "id, title, body, mood, visibility, created_at"],
  ["eq", "user_id", "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],
  ["gte", "created_at", "2026-07-31T15:00:00.000Z"],
  ["lt", "created_at", "2026-08-31T15:00:00.000Z"],
  ["is", "deleted_at", null],
  ["order", "created_at", { ascending: false }],
  ["order", "id", { ascending: false }],
  ["returns"],
]);

const runtimeTimezones = Array.from(
  new Set([...Intl.supportedValuesOf("timeZone"), "UTC"]),
);
for (const timezone of runtimeTimezones) {
  for (const month of [march, august]) {
    const range = getCalendarMonthUtcRange(month, timezone);
    const nextMonth = shiftCalendarMonth(month, 1);
    assert.ok(nextMonth);
    assert.equal(getCalendarMonthForInstant(range.start, timezone), month);
    assert.equal(getCalendarMonthForInstant(range.end, timezone), nextMonth);
    assert.equal(
      getCalendarMonthForInstant(Date.parse(range.end) - 1, timezone),
      month,
    );
  }
}

console.log(
  `calendar foundation assertions: PASS (${runtimeTimezones.length} runtime timezones swept)`,
);
