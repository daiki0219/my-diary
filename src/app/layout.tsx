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
      <body>
        <div className="mx-auto flex min-h-dvh w-full max-w-2xl flex-col bg-white shadow-sm">
          <header className="border-b border-stone-200 px-5 py-4">
            <p className="text-lg font-semibold tracking-tight text-stone-800">
              ゆる日記SNS
            </p>
          </header>
          <main className="flex flex-1 flex-col">{children}</main>
          <footer className="border-t border-stone-200 px-5 py-4 text-center text-xs text-stone-500">
            ありのままの毎日を、気軽に。
          </footer>
        </div>
      </body>
    </html>
  );
}
