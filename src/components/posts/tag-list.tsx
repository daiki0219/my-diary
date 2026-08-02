import type { PostTag } from "@/lib/tag-data";

export function TagList({ tags }: { tags: readonly PostTag[] }) {
  if (tags.length === 0) {
    return null;
  }

  return (
    <ul aria-label="タグ" className="mt-4 flex min-w-0 max-w-full flex-wrap gap-2">
      {tags.map((tag) => (
        <li className="min-w-0 max-w-full" key={tag.name}>
          <span className="block max-w-full break-words rounded-full border border-orange-200 bg-orange-50 px-3 py-1 text-xs font-medium text-orange-900 [overflow-wrap:anywhere]">
            #{tag.name}
          </span>
        </li>
      ))}
    </ul>
  );
}
