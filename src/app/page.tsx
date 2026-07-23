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
        <p className="mt-8 text-sm text-stone-500">
          現在、MVPの開発準備中です。
        </p>
      </div>
    </section>
  );
}
