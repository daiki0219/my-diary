"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import {
  ProtectedHeader,
  ProtectedMobileNavigation,
} from "@/components/layout/protected-app-navigation";
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

export function ProtectedSiteFrame({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const isAdminPath =
    pathname === "/admin" || pathname.startsWith("/admin/");
  const isWidePath =
    pathname === "/home" ||
    pathname === "/calendar" ||
    pathname === "/notifications" ||
    isPostDetailPath(pathname);

  return (
    <SiteFrame
      afterFooter={<ProtectedMobileNavigation />}
      headerContent={<ProtectedHeader />}
      headerInnerClassName="px-4 py-0 sm:px-5 lg:px-8"
      headerWidth={isAdminPath ? "default" : "shell"}
      showFooter={false}
      width={isWidePath ? "wide" : "default"}
    >
      {children}
    </SiteFrame>
  );
}
