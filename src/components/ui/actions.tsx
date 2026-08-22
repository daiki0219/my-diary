import Link from "next/link";
import type { ButtonHTMLAttributes, ComponentProps } from "react";

import { joinClassNames } from "@/components/ui/class-names";

export type ActionVariant =
  | "primary"
  | "secondary"
  | "neutral"
  | "destructive"
  | "quiet";

const actionVariantClassNames: Record<ActionVariant, string> = {
  primary:
    "bg-brand-primary px-5 font-semibold text-white hover:bg-brand-primary-hover",
  secondary:
    "bg-brand-soft px-5 font-semibold text-brand-primary-hover hover:bg-surface-muted",
  neutral:
    "border border-border-subtle bg-surface-elevated px-5 font-semibold text-text-secondary hover:bg-surface-muted hover:text-text-primary",
  destructive: "bg-danger px-5 font-semibold text-white hover:opacity-90",
  quiet:
    "px-3 font-medium text-text-secondary hover:bg-surface-muted hover:text-text-primary",
};

function actionClassName(variant: ActionVariant, className?: string) {
  return joinClassNames(
    "inline-flex min-h-11 items-center justify-center rounded-control py-2.5 text-center leading-6 transition disabled:cursor-wait disabled:bg-control-disabled disabled:text-control-disabled-text",
    actionVariantClassNames[variant],
    className,
  );
}

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ActionVariant;
};

export function Button({
  className,
  variant = "neutral",
  ...props
}: ButtonProps) {
  return (
    <button className={actionClassName(variant, className)} {...props} />
  );
}

type ActionLinkProps = ComponentProps<typeof Link> & {
  variant?: ActionVariant;
};

export function ActionLink({
  className,
  variant = "neutral",
  ...props
}: ActionLinkProps) {
  return (
    <Link
      className={actionClassName(
        variant,
        joinClassNames(
          "aria-disabled:pointer-events-none aria-disabled:opacity-60",
          className,
        ),
      )}
      {...props}
    />
  );
}
