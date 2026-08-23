import { ProtectedSiteFrame } from "@/components/layout/protected-site-frame";

export default function ProtectedLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return <ProtectedSiteFrame>{children}</ProtectedSiteFrame>;
}
