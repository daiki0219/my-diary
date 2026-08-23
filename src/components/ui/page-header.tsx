import type { ReactNode } from "react";

import { joinClassNames } from "@/components/ui/class-names";
import { Surface } from "@/components/ui/surface";

type PageHeaderProps = {
  className?: string;
  description?: ReactNode;
  eyebrow: ReactNode;
  title: ReactNode;
};

export function PageHeader({
  className,
  description,
  eyebrow,
  title,
}: PageHeaderProps) {
  return (
    <Surface
      className={joinClassNames("min-w-0 p-5 sm:p-7", className)}
      variant="muted"
    >
      <p className="text-sm font-medium text-brand-primary-hover">
        {eyebrow}
      </p>
      <h1 className="mt-2 break-words text-3xl font-semibold tracking-tight text-text-primary [overflow-wrap:anywhere]">
        {title}
      </h1>
      {description && (
        <p className="mt-3 break-words text-sm leading-6 text-text-secondary [overflow-wrap:anywhere]">
          {description}
        </p>
      )}
    </Surface>
  );
}
