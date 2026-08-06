export const SEARCH_CATEGORIES = ["users", "tags"] as const;

export type SearchCategory = (typeof SEARCH_CATEGORIES)[number];

export const SEARCH_QUERY_MAX_LENGTH: Record<SearchCategory, number> = {
  users: 50,
  tags: 30,
};

const CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f-\u009f]/u;

export type SearchQueryValidation = {
  query: string;
  error: string | null;
  isEmpty: boolean;
};

export type SingleQueryParam =
  | { status: "missing"; value: null }
  | { status: "valid"; value: string }
  | { status: "multiple"; value: null };

function hasLoneSurrogate(value: string) {
  for (let index = 0; index < value.length; index += 1) {
    const codeUnit = value.charCodeAt(index);

    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
      const nextCodeUnit = value.charCodeAt(index + 1);

      if (
        index + 1 >= value.length ||
        nextCodeUnit < 0xdc00 ||
        nextCodeUnit > 0xdfff
      ) {
        return true;
      }

      index += 1;
    } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
      return true;
    }
  }

  return false;
}

function trimAsciiSpaces(value: string) {
  return value.replace(/^ +| +$/gu, "");
}

export function normalizeTagSearchQuery(value: string) {
  let normalized = trimAsciiSpaces(value.normalize("NFKC"));
  normalized = normalized.replace(/^#+/u, "");
  normalized = trimAsciiSpaces(normalized);
  normalized = normalized.replace(/ +/gu, " ");
  return normalized.replace(/[A-Z]/gu, (character) =>
    character.toLowerCase(),
  );
}

export function isSearchCategory(value: string): value is SearchCategory {
  return SEARCH_CATEGORIES.some((category) => category === value);
}

export function readSingleQueryParam(
  value: string | string[] | undefined,
): SingleQueryParam {
  if (value === undefined) {
    return { status: "missing", value: null };
  }

  if (typeof value !== "string") {
    return { status: "multiple", value: null };
  }

  return { status: "valid", value };
}

export function validateSearchQuery(
  category: SearchCategory,
  rawQuery: string,
): SearchQueryValidation {
  if (hasLoneSurrogate(rawQuery)) {
    return {
      query: "",
      error: "検索語に使用できない文字が含まれています。",
      isEmpty: false,
    };
  }

  const query =
    category === "tags"
      ? normalizeTagSearchQuery(rawQuery)
      : rawQuery.normalize("NFKC").trim();

  if (query.length === 0) {
    return { query: "", error: null, isEmpty: true };
  }

  if (CONTROL_CHARACTER_PATTERN.test(query)) {
    return {
      query,
      error: "検索語に改行、タブ、制御文字は使用できません。",
      isEmpty: false,
    };
  }

  if (category === "tags" && (query.includes(",") || query.includes("#"))) {
    return {
      query,
      error: "タグ検索には途中の#やカンマは使用できません。",
      isEmpty: false,
    };
  }

  const maxLength = SEARCH_QUERY_MAX_LENGTH[category];

  if (Array.from(query).length > maxLength) {
    return {
      query,
      error: `検索語は${maxLength}文字以下で入力してください。`,
      isEmpty: false,
    };
  }

  return { query, error: null, isEmpty: false };
}

export function buildSearchUrl({
  category,
  query,
  cursor,
}: {
  category: SearchCategory;
  query?: string;
  cursor?: string;
}) {
  const params = new URLSearchParams({ category });

  if (query) {
    params.set("q", query);
  }

  if (cursor) {
    params.set("cursor", cursor);
  }

  return `/search?${params.toString()}`;
}
