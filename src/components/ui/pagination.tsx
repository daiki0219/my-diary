import type { ComponentProps, ComponentPropsWithoutRef } from "react";

import { ActionLink } from "@/components/ui/actions";
import { joinClassNames } from "@/components/ui/class-names";

type PaginationProps = ComponentPropsWithoutRef<"nav">;

export function Pagination({ className, ...props }: PaginationProps) {
  return (
    <nav
      className={joinClassNames("flex min-w-0 flex-wrap gap-3", className)}
      {...props}
    />
  );
}

type PaginationLinkProps = Omit<
  ComponentProps<typeof ActionLink>,
  "variant"
>;

export function PaginationLink({
  className,
  ...props
}: PaginationLinkProps) {
  return (
    <ActionLink
      {...props}
      className={joinClassNames(
        "min-w-0 gap-2 bg-surface-muted px-5 text-text-secondary hover:bg-brand-soft hover:text-brand-primary-hover",
        className,
      )}
      variant="quiet"
    />
  );
}
