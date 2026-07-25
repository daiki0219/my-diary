import Link from "next/link";

export default function Home() {
  return (
    <section className="flex flex-1 items-center px-5 py-12 sm:px-8">
      <div className="w-full rounded-3xl bg-orange-50 px-6 py-10 text-center sm:px-10 sm:py-14">
        <p className="mb-3 text-sm font-medium text-orange-700">
          ゆるく続ける、わたしの日記
        </p>
        <h1 className="text-3xl font-bold tracking-tight text-stone-800 sm:text-4xl">
          今日のことを、
          <br />
          そのまま残そう。
        </h1>
        <p className="mx-auto mt-5 max-w-md text-base leading-7 text-stone-600">
          ありのままの毎日を気軽に記録し、必要なときだけ誰かとゆるくつながれる場所です。
        </p>
        <div className="mx-auto mt-8 flex max-w-sm flex-col gap-3 sm:flex-row">
          <Link
            className="flex-1 rounded-full bg-orange-600 px-5 py-3 font-semibold text-white transition hover:bg-orange-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/sign-up"
          >
            新規登録
          </Link>
          <Link
            className="flex-1 rounded-full border border-orange-300 bg-white px-5 py-3 font-semibold text-orange-800 transition hover:bg-orange-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-orange-600"
            href="/login"
          >
            ログイン
          </Link>
        </div>
      </div>
    </section>
  );
}
