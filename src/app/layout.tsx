import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "ゆる日記SNS",
    template: "%s | ゆる日記SNS",
  },
  description: "ありのままの毎日を、気軽に記録して、ゆるくつながる。",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
