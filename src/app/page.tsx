import Image from "next/image";

import { SiteFrame } from "@/components/layout/site-frame";
import { ActionLink } from "@/components/ui/actions";
import { Surface } from "@/components/ui/surface";

export default function Home() {
  return (
    <SiteFrame>
      <section className="flex flex-1 items-center px-5 py-12 sm:px-8">
        <Surface
          className="w-full px-6 py-10 text-center shadow-surface sm:px-10 sm:py-14"
          variant="muted"
        >
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
            <ActionLink
              className="flex-1"
              href="/sign-up"
              variant="primary"
            >
              新規登録
            </ActionLink>
            <ActionLink
              className="flex-1"
              href="/login"
              variant="secondary"
            >
              ログイン
            </ActionLink>
          </div>
        </Surface>
      </section>
    </SiteFrame>
  );
}
