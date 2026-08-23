import type { ReactNode } from "react";

import { joinClassNames } from "@/components/ui/class-names";

type SiteFrameWidth = "default" | "wide" | "shell";

type SiteFrameProps = {
  afterFooter?: ReactNode;
  children: ReactNode;
  headerContent?: ReactNode;
  headerInnerClassName?: string;
  headerWidth?: SiteFrameWidth;
  showFooter?: boolean;
  width?: SiteFrameWidth;
};

function widthClassName(width: SiteFrameWidth) {
  if (width === "shell") {
    return "xl:max-w-[85rem]";
  }

  if (width === "wide") {
    return "max-w-2xl lg:max-w-5xl";
  }

  return "max-w-2xl";
}

export function SiteFrame({
  afterFooter,
  children,
  headerContent,
  headerInnerClassName,
  headerWidth,
  showFooter = true,
  width = "default",
}: SiteFrameProps) {
  const contentWidthClassName = widthClassName(width);
  const headerWidthClassName = widthClassName(headerWidth ?? width);

  return (
    <div className="flex min-h-dvh w-full flex-col bg-transparent">
      <header className="border-b border-border-subtle/60 bg-surface/50">
        <div
          className={joinClassNames(
            "mx-auto w-full px-5 py-3",
            headerWidthClassName,
            headerInnerClassName,
          )}
        >
          {headerContent ?? (
            <p className="font-brand text-2xl font-medium tracking-tight text-text-primary">
              my-diary
            </p>
          )}
        </div>
      </header>
      <main className="flex flex-1 flex-col">
        <div
          className={joinClassNames(
            "mx-auto flex w-full flex-1 flex-col",
            contentWidthClassName,
          )}
        >
          {children}
        </div>
      </main>
      {showFooter && (
        <footer className="bg-surface/30 px-5 pb-8 pt-5 text-center text-xs text-text-muted">
          <div className={joinClassNames("mx-auto w-full", contentWidthClassName)}>
            ありのままの毎日を、気軽に。
          </div>
        </footer>
      )}
      {afterFooter}
    </div>
  );
}
