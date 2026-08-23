import Link from "next/link";

import type { PostTag } from "@/lib/tag-data";

export function TagList({
  tags,
  variant = "default",
}: {
  tags: readonly PostTag[];
  variant?: "default" | "timeline";
}) {
  if (tags.length === 0) {
    return null;
  }

  return (
    <ul
      aria-label="タグ"
      className={`flex min-w-0 max-w-full flex-wrap ${
        variant === "timeline" ? "mt-3 gap-1.5" : "mt-4 gap-2"
      }`}
    >
      {tags.map((tag) => (
        <li className="min-w-0 max-w-full" key={tag.id}>
          <Link
            className={`inline-flex max-w-full items-center break-words rounded-full text-xs underline-offset-2 [overflow-wrap:anywhere] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600 ${
              variant === "timeline"
                ? "min-h-10 bg-brand-soft/70 px-2.5 py-1 font-medium text-brand-primary-hover hover:bg-brand-soft hover:underline"
                : "min-h-10 border border-orange-300 bg-orange-50 px-3 py-1 font-semibold text-orange-900 hover:bg-orange-100 hover:underline"
            }`}
            href={`/tags/${tag.id}`}
          >
            #{tag.name}
          </Link>
        </li>
      ))}
    </ul>
  );
}
