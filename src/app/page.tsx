import Image from "next/image";
import Link from "next/link";

export default function Home() {
  return (
    <section className="flex flex-1 items-center px-5 py-12 sm:px-8">
      <div className="w-full rounded-card bg-surface-muted px-6 py-10 text-center shadow-surface sm:px-10 sm:py-14">
        <Image
          alt=""
          aria-hidden="true"
          className="mx-auto mb-4 h-auto w-14 opacity-85"
          height={724}
          sizes="56px"
          src="/images/brand/diary-sprig.png"
          width={664}
        />
        <p className="mb-3 text-sm font-medium text-brand-primary-hover">
          ゆるく続ける、わたしの日記
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-text-primary sm:text-4xl">
          今日のことを、
          <br />
          そのまま残そう。
        </h1>
        <p className="mx-auto mt-5 max-w-md text-base leading-7 text-text-secondary">
          ありのままの毎日を気軽に記録し、必要なときだけ誰かとゆるくつながれる場所です。
        </p>
        <div className="mx-auto mt-8 flex max-w-sm flex-col gap-3 sm:flex-row">
          <Link
            className="flex-1 rounded-control bg-brand-primary px-5 py-3 font-semibold text-white transition hover:bg-brand-primary-hover"
            href="/sign-up"
          >
            新規登録
          </Link>
          <Link
            className="flex-1 rounded-control border border-border-subtle bg-surface-elevated px-5 py-3 font-semibold text-brand-primary-hover transition hover:bg-brand-soft"
            href="/login"
          >
            ログイン
          </Link>
        </div>
      </div>
    </section>
  );
}
