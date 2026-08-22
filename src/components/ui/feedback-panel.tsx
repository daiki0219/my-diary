import {
  createElement,
  type HTMLAttributes,
  type ReactNode,
} from "react";

import { joinClassNames } from "@/components/ui/class-names";

export type FeedbackVariant = "error" | "success" | "warning" | "neutral";

const feedbackVariantClassNames: Record<FeedbackVariant, string> = {
  error: "border-danger/20 bg-danger/5 text-danger",
  success: "border-success/20 bg-success/5 text-success",
  warning: "border-warning/25 bg-warning/10 text-warning",
  neutral: "border-border-subtle bg-surface-muted text-text-secondary",
};

const feedbackVariantMarks: Record<FeedbackVariant, string> = {
  error: "×",
  success: "✓",
  warning: "!",
  neutral: "i",
};

type FeedbackPanelProps = Omit<HTMLAttributes<HTMLDivElement>, "title"> & {
  title?: ReactNode;
  titleAs?: "h2" | "h3";
  variant?: FeedbackVariant;
};

export function FeedbackPanel({
  children,
  className,
  title,
  titleAs = "h2",
  variant = "neutral",
  ...props
}: FeedbackPanelProps) {
  return (
    <div
      className={joinClassNames(
        "flex min-w-0 items-start gap-3 rounded-control border px-4 py-3 text-sm leading-6",
        feedbackVariantClassNames[variant],
        className,
      )}
      {...props}
    >
      <span
        aria-hidden="true"
        className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border border-current text-xs font-bold leading-none"
      >
        {feedbackVariantMarks[variant]}
      </span>
      <div className="min-w-0 flex-1 break-words [overflow-wrap:anywhere]">
        {title &&
          createElement(
            titleAs,
            { className: "font-semibold text-text-primary" },
            title,
          )}
        <div className={title ? "mt-1" : undefined}>{children}</div>
      </div>
    </div>
  );
}
