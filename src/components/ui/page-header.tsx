import type { ReactNode } from "react";

import { joinClassNames } from "@/components/ui/class-names";
import { Surface } from "@/components/ui/surface";

type PageHeaderProps = {
  className?: string;
  description?: ReactNode;
  eyebrow?: ReactNode;
  title: ReactNode;
  variant?: "muted" | "plain";
};

export function PageHeader({
  className,
  description,
  eyebrow,
  title,
  variant = "muted",
}: PageHeaderProps) {
  const content = (
    <>
      {Boolean(eyebrow) && (
        <p className="text-sm font-medium text-brand-primary-hover">
          {eyebrow}
        </p>
      )}
      <h1
        className={joinClassNames(
          "break-words font-semibold tracking-tight text-text-primary [overflow-wrap:anywhere]",
          Boolean(eyebrow) && "mt-2",
          variant === "plain" ? "text-2xl sm:text-3xl" : "text-3xl",
        )}
      >
        {title}
      </h1>
      {description && (
        <p
          className={joinClassNames(
            "break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]",
            variant === "plain" ? "mt-2" : "mt-3",
          )}
        >
          {description}
        </p>
      )}
    </>
  );

  if (variant === "plain") {
    return (
      <div className={joinClassNames("min-w-0 py-1", className)}>
        {content}
      </div>
    );
  }

  return (
    <Surface
      className={joinClassNames("min-w-0 p-5 sm:p-7", className)}
      variant="muted"
    >
      {content}
    </Surface>
  );
}
