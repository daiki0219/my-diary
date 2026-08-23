import { SiteFrame } from "@/components/layout/site-frame";

export default function ProtectedLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return <SiteFrame>{children}</SiteFrame>;
}
