"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import {
  ProtectedHeader,
  ProtectedMobileNavigation,
} from "@/components/layout/protected-app-navigation";
import { ProtectedMoreMenu } from "@/components/layout/protected-more-menu";
import { SiteFrame } from "@/components/layout/site-frame";
import { isUuid } from "@/lib/profile-data";

function isPostDetailPath(pathname: string) {
  const segments = pathname.split("/").filter(Boolean);
  const postId = segments[1];

  return (
    segments.length === 2 &&
    segments[0] === "posts" &&
    typeof postId === "string" &&
    isUuid(postId)
  );
}

function isExchangeDiaryDetailPath(pathname: string) {
  const segments = pathname.split("/").filter(Boolean);
  const diaryId = segments[1];

  return (
    segments.length === 2 &&
    segments[0] === "exchange" &&
    typeof diaryId === "string" &&
    isUuid(diaryId)
  );
}

function isExchangeEntryFormPath(pathname: string) {
  const segments = pathname.split("/").filter(Boolean);
  const diaryId = segments[1];

  if (
    segments[0] !== "exchange" ||
    !diaryId ||
    !isUuid(diaryId) ||
    segments[2] !== "entries"
  ) {
    return false;
  }

  if (segments.length === 4) {
    return segments[3] === "new";
  }

  const entryId = segments[3];

  return (
    segments.length === 5 &&
    typeof entryId === "string" &&
    isUuid(entryId) &&
    segments[4] === "edit"
  );
}

export function ProtectedSiteFrame({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isAdminPath =
    pathname === "/admin" || pathname.startsWith("/admin/");
  const isWidePath =
    pathname === "/home" ||
    pathname === "/calendar" ||
    pathname === "/notifications" ||
    pathname === "/exchange" ||
    isExchangeDiaryDetailPath(pathname) ||
    isExchangeEntryFormPath(pathname) ||
    isPostDetailPath(pathname);

  return (
    <ProtectedMoreMenu key={pathname}>
      {({ desktopTrigger, mobileTrigger }) => (
        <SiteFrame
          afterFooter={
            <>
              {mobileTrigger}
              <ProtectedMobileNavigation />
            </>
          }
          headerContent={
            <ProtectedHeader moreMenuTrigger={desktopTrigger} />
          }
          headerInnerClassName="px-4 py-0 sm:px-5 lg:px-8"
          headerWidth={isAdminPath ? "default" : "shell"}
          showFooter={false}
          width={isWidePath ? "wide" : "default"}
        >
          {children}
        </SiteFrame>
      )}
    </ProtectedMoreMenu>
  );
}
