"use client";

import { usePathname } from "next/navigation";
import type { ReactNode } from "react";

import {
  ProtectedHeader,
  ProtectedMobileNavigation,
} from "@/components/layout/protected-app-navigation";
import { SiteFrame } from "@/components/layout/site-frame";

export function ProtectedSiteFrame({ children }: { children: ReactNode }) {
  const pathname = usePathname();

  return (
    <SiteFrame
      afterFooter={<ProtectedMobileNavigation />}
      headerContent={<ProtectedHeader />}
      width={pathname === "/home" ? "wide" : "default"}
    >
      {children}
    </SiteFrame>
  );
}
