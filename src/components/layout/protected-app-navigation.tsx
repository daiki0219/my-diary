"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import { joinClassNames } from "@/components/ui/class-names";

const primaryItems = [
  { href: "/home", icon: "home", label: "ホーム" },
  { href: "/calendar", icon: "calendar", label: "カレンダー" },
  { href: "/notifications", icon: "notification", label: "通知" },
  { href: "/profile", icon: "profile", label: "プロフィール" },
] as const;

type NavigationIconName =
  | "calendar"
  | "home"
  | "notification"
  | "profile"
  | "search";

function NavigationIcon({
  className,
  name,
}: {
  className?: string;
  name: NavigationIconName;
}) {
  const paths: Record<NavigationIconName, ReactNode> = {
    calendar: (
      <>
        <rect height="16" rx="2" width="18" x="3" y="5" />
        <path d="M8 3v4M16 3v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01" />
      </>
    ),
    home: (
      <>
        <path d="m3 11 9-8 9 8" />
        <path d="M5 10v10h14V10M9 20v-6h6v6" />
      </>
    ),
    notification: (
      <>
        <path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" />
        <path d="M10 21h4" />
      </>
    ),
    profile: (
      <>
        <circle cx="12" cy="8" r="4" />
        <path d="M4 21a8 8 0 0 1 16 0" />
      </>
    ),
    search: (
      <>
        <circle cx="11" cy="11" r="7" />
        <path d="m20 20-4-4" />
      </>
    ),
  };

  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      focusable="false"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeWidth="1.8"
      viewBox="0 0 24 24"
    >
      {paths[name]}
    </svg>
  );
}

function isAdminPath(pathname: string) {
  return pathname === "/admin" || pathname.startsWith("/admin/");
}

function isPrimaryItemCurrent(pathname: string, href: string) {
  if (
    href === "/calendar" ||
    href === "/notifications" ||
    href === "/profile"
  ) {
    return pathname === href || pathname.startsWith(`${href}/`);
  }

  return pathname === href;
}

function primaryLinkClassName(isCurrent: boolean, isMobile = false) {
  return joinClassNames(
    "flex items-center justify-center text-center transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-primary",
    isMobile
      ? "min-h-[53px] flex-col gap-0.5 rounded-lg px-1 py-1 text-[11px] leading-4 tracking-tight"
      : "h-full gap-2 border-b-2 px-2 py-2 text-sm leading-5 xl:px-3",
    isCurrent && isMobile && "font-semibold text-brand-primary-hover",
    isCurrent && !isMobile &&
      "border-brand-primary font-semibold text-brand-primary-hover",
    !isCurrent && isMobile &&
      "font-medium text-text-secondary hover:bg-surface-muted hover:text-text-primary",
    !isCurrent && !isMobile &&
      "border-transparent font-medium text-text-secondary hover:border-border-subtle hover:text-text-primary",
  );
}

export const protectedHeaderUtilityClassName =
  "inline-flex size-11 shrink-0 items-center justify-center rounded-full text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-primary";

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
        <span
          className={joinClassNames(
            "flex items-center justify-center",
            mobile && "h-7 w-9 rounded-full transition",
            mobile && isCurrent && "bg-brand-soft",
          )}
        >
          <NavigationIcon
            className={mobile ? "size-[22px]" : "size-5"}
            name={item.icon}
          />
        </span>
        <span>{item.label}</span>
      </Link>
    );
  });
}

export function ProtectedHeader({
  mobileMoreMenuTrigger,
  moreMenuTrigger,
}: {
  mobileMoreMenuTrigger?: ReactNode;
  moreMenuTrigger?: ReactNode;
}) {
  const pathname = usePathname();

  if (isAdminPath(pathname)) {
    return (
      <div className="flex h-16 items-center justify-between gap-2">
        <p className="font-brand text-2xl font-medium tracking-tight text-text-primary">
          my-diary
        </p>
        <div className="shrink-0">
          <div className="lg:hidden">{mobileMoreMenuTrigger}</div>
          <div className="hidden lg:block">{moreMenuTrigger}</div>
        </div>
      </div>
    );
  }

  const isSearchCurrent = pathname === "/search";

  return (
    <div className="flex h-[52px] min-w-0 items-center justify-between gap-2 lg:h-24 lg:gap-6">
      <Link
        className="shrink-0 rounded-sm font-brand text-[1.75rem] font-medium tracking-tight text-text-primary focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand-primary lg:text-4xl"
        href="/home"
      >
        my-diary
      </Link>
      <nav
        aria-label="主要ナビゲーション"
        className="hidden h-full min-w-0 items-center gap-1 lg:flex"
      >
        <PrimaryLinks />
      </nav>
      <div className="flex shrink-0 items-center gap-0.5 lg:hidden">
        <Link
          aria-current={isSearchCurrent ? "page" : undefined}
          aria-label="検索"
          className={joinClassNames(
            protectedHeaderUtilityClassName,
            isSearchCurrent && "bg-brand-soft text-brand-primary-hover",
          )}
          href="/search"
        >
          <NavigationIcon className="size-6" name="search" />
        </Link>
        {mobileMoreMenuTrigger}
      </div>
      <div className="hidden shrink-0 items-center gap-1 lg:flex">
        <Link
          aria-current={isSearchCurrent ? "page" : undefined}
          aria-label="検索"
          className={joinClassNames(
            protectedHeaderUtilityClassName,
            isSearchCurrent && "bg-brand-soft text-brand-primary-hover",
          )}
          href="/search"
        >
          <NavigationIcon className="size-6" name="search" />
        </Link>
        {moreMenuTrigger}
      </div>
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
        className="lg:hidden"
        style={{ height: "calc(53px + env(safe-area-inset-bottom))" }}
      />
      <nav
        aria-label="主要ナビゲーション"
        className="fixed inset-x-0 bottom-0 z-40 border-t border-border-subtle/60 bg-surface/95 lg:hidden"
        style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
      >
        <div className="mx-auto grid h-[53px] w-full max-w-2xl grid-cols-4 px-1">
          <PrimaryLinks mobile />
        </div>
      </nav>
    </>
  );
}
