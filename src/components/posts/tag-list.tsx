import Link from "next/link";

import type { PostTag } from "@/lib/tag-data";

export function TagList({ tags }: { tags: readonly PostTag[] }) {
  if (tags.length === 0) {
    return null;
  }

  return (
    <ul aria-label="タグ" className="mt-4 flex min-w-0 max-w-full flex-wrap gap-2">
      {tags.map((tag) => (
        <li className="min-w-0 max-w-full" key={tag.id}>
          <Link
            className="inline-flex min-h-10 max-w-full items-center break-words rounded-full border border-orange-300 bg-orange-50 px-3 py-1 text-xs font-semibold text-orange-900 underline-offset-2 [overflow-wrap:anywhere] hover:bg-orange-100 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href={`/tags/${tag.id}`}
          >
            #{tag.name}
          </Link>
        </li>
      ))}
    </ul>
  );
}
