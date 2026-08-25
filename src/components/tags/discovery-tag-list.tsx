import Link from "next/link";

import { joinClassNames } from "@/components/ui/class-names";

type DiscoveryTag = {
  id: string;
  name: string;
};

export function DiscoveryTagList({
  ariaLabel,
  className,
  tags,
}: {
  ariaLabel: string;
  className?: string;
  tags: readonly DiscoveryTag[];
}) {
  return (
    <ul
      aria-label={ariaLabel}
      className={joinClassNames(
        "grid min-w-0 gap-2 sm:grid-cols-2 sm:gap-3",
        className,
      )}
    >
      {tags.map((tag) => (
        <li className="min-w-0" key={tag.id}>
          <Link
            className="group flex min-h-14 min-w-0 items-center gap-3 rounded-control bg-surface-muted/70 px-4 py-3 transition hover:bg-brand-soft/70 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
            href={`/tags/${tag.id}`}
          >
            <span className="min-w-0 flex-1">
              <span className="block break-words font-semibold text-brand-primary-hover [overflow-wrap:anywhere]">
                #{tag.name}
              </span>
              <span className="mt-0.5 block text-xs text-text-muted">
                このタグの日記を見る
              </span>
            </span>
            <span
              aria-hidden="true"
              className="shrink-0 text-text-muted transition-transform group-hover:translate-x-0.5 group-hover:text-brand-primary-hover"
            >
              →
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}
