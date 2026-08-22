import {
  createElement,
  type HTMLAttributes,
  type ReactNode,
} from "react";

import { joinClassNames } from "@/components/ui/class-names";

type EmptyStateProps = Omit<HTMLAttributes<HTMLDivElement>, "title"> & {
  action?: ReactNode;
  decoration?: ReactNode;
  description?: ReactNode;
  title: ReactNode;
  titleAs?: "h2" | "h3";
};

export function EmptyState({
  action,
  className,
  decoration,
  description,
  title,
  titleAs = "h2",
  ...props
}: EmptyStateProps) {
  return (
    <div
      className={joinClassNames(
        "min-w-0 rounded-card bg-surface-muted px-5 py-8 text-center sm:px-8 sm:py-10",
        className,
      )}
      {...props}
    >
      {decoration && <div className="mb-4">{decoration}</div>}
      {createElement(
        titleAs,
        {
          className:
            "break-words text-lg font-semibold leading-7 text-text-primary [overflow-wrap:anywhere]",
        },
        title,
      )}
      {description && (
        <p className="mt-2 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
          {description}
        </p>
      )}
      {action && <div className="mt-5 flex justify-center">{action}</div>}
    </div>
  );
}
