import type {
  InputHTMLAttributes,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from "react";

import { joinClassNames } from "@/components/ui/class-names";

const formControlClassName =
  "min-h-11 w-full rounded-control border border-border-control bg-surface px-4 py-3 text-base text-text-primary transition placeholder:text-text-muted focus:border-focus aria-invalid:border-danger disabled:cursor-not-allowed disabled:border-control-disabled disabled:bg-surface-muted disabled:text-control-disabled-text";

export function FormInput({
  className,
  ...props
}: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input className={joinClassNames(formControlClassName, className)} {...props} />
  );
}

export function FormTextarea({
  className,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={joinClassNames(formControlClassName, className)}
      {...props}
    />
  );
}

export function FormSelect({
  className,
  ...props
}: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select className={joinClassNames(formControlClassName, className)} {...props} />
  );
}
