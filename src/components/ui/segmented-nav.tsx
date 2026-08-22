import Link from "next/link";
import type { ComponentProps, ComponentPropsWithoutRef } from "react";

import { joinClassNames } from "@/components/ui/class-names";

type SegmentedNavProps = ComponentPropsWithoutRef<"nav">;

export function SegmentedNav({ className, ...props }: SegmentedNavProps) {
  return (
    <nav
      className={joinClassNames(
        "flex min-w-0 gap-1 rounded-control bg-surface-muted p-1",
        className,
      )}
      {...props}
    />
  );
}

type SegmentedNavLinkProps = Omit<
  ComponentProps<typeof Link>,
  "aria-current"
> & {
  isCurrent: boolean;
};

export function SegmentedNavLink({
  children,
  className,
  isCurrent,
  ...props
}: SegmentedNavLinkProps) {
  return (
    <Link
      {...props}
      aria-current={isCurrent ? "page" : undefined}
      className={joinClassNames(
        "flex min-h-11 min-w-0 flex-1 items-center justify-center rounded-xl border px-3 py-2.5 text-center text-sm leading-5 transition",
        isCurrent
          ? "border-border-subtle bg-surface-elevated font-semibold text-brand-primary-hover shadow-surface"
          : "border-transparent font-medium text-text-secondary hover:bg-surface-elevated/70 hover:text-text-primary",
        className,
      )}
    >
      <span className="min-w-0 break-words [overflow-wrap:anywhere]">
        {children}
      </span>
    </Link>
  );
}
