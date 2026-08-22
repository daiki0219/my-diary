import {
  createElement,
  type FieldsetHTMLAttributes,
  type HTMLAttributes,
} from "react";

import { joinClassNames } from "@/components/ui/class-names";

export type SurfaceVariant = "default" | "elevated" | "muted";

const surfaceVariantClassNames: Record<SurfaceVariant, string> = {
  default: "bg-surface",
  elevated: "bg-surface-elevated shadow-surface",
  muted: "bg-surface-muted",
};

type SurfaceElement = "article" | "div" | "fieldset" | "section";

type SurfaceBaseProps = {
  variant?: SurfaceVariant;
};

type SurfaceProps =
  | (HTMLAttributes<HTMLDivElement> & SurfaceBaseProps & { as?: "div" })
  | (HTMLAttributes<HTMLElement> &
      SurfaceBaseProps & { as: "article" | "section" })
  | (FieldsetHTMLAttributes<HTMLFieldSetElement> &
      SurfaceBaseProps & { as: "fieldset" });

export function Surface({
  as = "div",
  className,
  variant = "default",
  ...props
}: SurfaceProps) {
  return createElement(as as SurfaceElement, {
    ...props,
    className: joinClassNames(
      "rounded-card",
      surfaceVariantClassNames[variant],
      className,
    ),
  });
}
