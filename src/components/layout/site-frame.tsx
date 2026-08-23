import type { ReactNode } from "react";

type SiteFrameProps = {
  afterFooter?: ReactNode;
  children: ReactNode;
  headerContent?: ReactNode;
};

export function SiteFrame({
  afterFooter,
  children,
  headerContent,
}: SiteFrameProps) {
  return (
    <div className="mx-auto flex min-h-dvh w-full max-w-2xl flex-col bg-transparent">
      <header className="border-b border-border-subtle bg-surface/80 px-5 py-4">
        {headerContent ?? (
          <p className="font-brand text-2xl font-medium tracking-tight text-text-primary">
            my-diary
          </p>
        )}
      </header>
      <main className="flex flex-1 flex-col">{children}</main>
      <footer className="border-t border-border-subtle bg-surface/70 px-5 py-4 text-center text-xs text-text-muted">
        ありのままの毎日を、気軽に。
      </footer>
      {afterFooter}
    </div>
  );
}
