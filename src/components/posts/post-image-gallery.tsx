"use client";

import Image from "next/image";
import { useState } from "react";

import type { PostImageReference } from "@/lib/post-image-data";

function PostImage({
  eager,
  image,
  index,
  isOnlyImage,
  total,
}: {
  eager: boolean;
  image: PostImageReference;
  index: number;
  isOnlyImage: boolean;
  total: number;
}) {
  const [failed, setFailed] = useState(false);
  const label = `投稿画像 ${index + 1} / ${total}`;

  return (
    <li
      className={`relative min-w-0 overflow-hidden rounded-2xl border border-stone-200 bg-stone-100 ${
        isOnlyImage ? "aspect-[4/3]" : "aspect-square"
      }`}
    >
      {failed ? (
        <div className="flex size-full items-center justify-center px-3 text-center text-xs leading-5 text-stone-500">
          <span className="sr-only">{label}: </span>
          画像を表示できません
        </div>
      ) : (
        <Image
          alt={label}
          className="object-contain"
          decoding="async"
          fill
          loading={eager ? "eager" : "lazy"}
          onError={() => setFailed(true)}
          sizes={
            isOnlyImage
              ? "(max-width: 639px) calc(100vw - 72px), 440px"
              : "(max-width: 639px) calc((100vw - 80px) / 2), 145px"
          }
          src={`/post-images/${image.id}`}
          unoptimized
        />
      )}
    </li>
  );
}

export function PostImageGallery({
  eagerFirst = false,
  images,
}: {
  eagerFirst?: boolean;
  images: readonly PostImageReference[];
}) {
  if (images.length === 0) {
    return null;
  }

  const isOnlyImage = images.length === 1;
  const columns = isOnlyImage
    ? "grid-cols-1"
    : images.length === 2
      ? "grid-cols-2"
      : "grid-cols-2 sm:grid-cols-3";

  return (
    <ol
      aria-label="投稿画像"
      className={`mt-5 grid min-w-0 gap-2 sm:gap-3 ${columns}`}
    >
      {images.map((image, index) => (
        <PostImage
          eager={eagerFirst && index === 0}
          image={image}
          index={index}
          isOnlyImage={isOnlyImage}
          key={image.id}
          total={images.length}
        />
      ))}
    </ol>
  );
}
