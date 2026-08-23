"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { joinClassNames } from "@/components/ui/class-names";

const primaryItems = [
  { href: "/home", label: "ホーム" },
  { href: "/calendar", label: "カレンダー" },
  { href: "/notifications", label: "通知" },
  { href: "/profile", label: "プロフィール" },
] as const;

function isAdminPath(pathname: string) {
  return pathname === "/admin" || pathname.startsWith("/admin/");
}

function isPrimaryItemCurrent(pathname: string, href: string) {
  if (href === "/profile") {
    return pathname === href || pathname.startsWith(`${href}/`);
  }

  return pathname === href;
}

function primaryLinkClassName(isCurrent: boolean, isMobile = false) {
  return joinClassNames(
    "flex items-center justify-center rounded-control text-center transition",
    isMobile
      ? "m-1 min-h-14 px-0 text-[13px] leading-5 tracking-tight"
      : "min-h-11 px-2 py-2 text-sm leading-5",
    isCurrent
      ? "bg-brand-soft font-semibold text-brand-primary-hover"
      : "font-medium text-text-secondary hover:bg-surface-muted hover:text-text-primary",
  );
}

function PrimaryLinks({ mobile = false }: { mobile?: boolean }) {
  const pathname = usePathname();

  return primaryItems.map((item) => {
    const isCurrent = isPrimaryItemCurrent(pathname, item.href);

    return (
      <Link
        aria-current={isCurrent ? "page" : undefined}
        className={primaryLinkClassName(isCurrent, mobile)}
        href={item.href}
        key={item.href}
      >
        {item.label}
      </Link>
    );
  });
}

export function ProtectedHeader() {
  const pathname = usePathname();

  if (isAdminPath(pathname)) {
    return (
      <p className="font-brand text-2xl font-medium tracking-tight text-text-primary">
        my-diary
      </p>
    );
  }

  const isSearchCurrent = pathname === "/search";

  return (
    <div className="flex min-w-0 items-center justify-between gap-3">
      <Link
        className="shrink-0 rounded-sm font-brand text-2xl font-medium tracking-tight text-text-primary"
        href="/home"
      >
        my-diary
      </Link>
      <nav
        aria-label="主要ナビゲーション"
        className="hidden min-w-0 items-center gap-1 sm:flex"
      >
        <PrimaryLinks />
      </nav>
      <Link
        aria-current={isSearchCurrent ? "page" : undefined}
        className={joinClassNames(
          "hidden min-h-11 shrink-0 items-center justify-center rounded-control px-3 py-2 text-sm leading-5 transition sm:flex",
          isSearchCurrent
            ? "bg-brand-soft font-semibold text-brand-primary-hover"
            : "font-medium text-text-secondary hover:bg-surface-muted hover:text-text-primary",
        )}
        href="/search"
      >
        検索
      </Link>
    </div>
  );
}

export function ProtectedMobileNavigation() {
  const pathname = usePathname();

  if (isAdminPath(pathname)) {
    return null;
  }

  return (
    <>
      <div
        aria-hidden="true"
        className="sm:hidden"
        style={{ height: "calc(4rem + env(safe-area-inset-bottom))" }}
      />
      <nav
        aria-label="主要ナビゲーション"
        className="fixed inset-x-0 bottom-0 z-40 border-t border-border-subtle bg-surface/95 sm:hidden"
        style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
      >
        <div className="mx-auto grid w-full max-w-2xl grid-cols-4 px-1">
          <PrimaryLinks mobile />
        </div>
      </nav>
    </>
  );
}
