"use client";

import Image from "next/image";
import { useState } from "react";

import type { PostImageReference } from "@/lib/post-image-data";

type PostImageGalleryVariant = "post" | "exchange-entry";

const galleryPresentation = {
  post: {
    imagePathPrefix: "/post-images",
    label: "投稿画像",
  },
  "exchange-entry": {
    imagePathPrefix: "/exchange-entry-images",
    label: "交換日記の画像",
  },
} as const satisfies Record<
  PostImageGalleryVariant,
  { imagePathPrefix: string; label: string }
>;

function PostImage({
  eager,
  image,
  imagePathPrefix,
  index,
  isOnlyImage,
  labelPrefix,
  total,
}: {
  eager: boolean;
  image: PostImageReference;
  imagePathPrefix: (typeof galleryPresentation)[PostImageGalleryVariant]["imagePathPrefix"];
  index: number;
  isOnlyImage: boolean;
  labelPrefix: (typeof galleryPresentation)[PostImageGalleryVariant]["label"];
  total: number;
}) {
  const [failed, setFailed] = useState(false);
  const label = `${labelPrefix} ${index + 1} / ${total}`;

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
          src={`${imagePathPrefix}/${image.id}`}
          unoptimized
        />
      )}
    </li>
  );
}

export function PostImageGallery({
  eagerFirst = false,
  images,
  variant = "post",
}: {
  eagerFirst?: boolean;
  images: readonly PostImageReference[];
  variant?: PostImageGalleryVariant;
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
  const presentation = galleryPresentation[variant];

  return (
    <ol
      aria-label={presentation.label}
      className={`mt-5 grid min-w-0 gap-2 sm:gap-3 ${columns}`}
    >
      {images.map((image, index) => (
        <PostImage
          eager={eagerFirst && index === 0}
          image={image}
          imagePathPrefix={presentation.imagePathPrefix}
          index={index}
          isOnlyImage={isOnlyImage}
          key={image.id}
          labelPrefix={presentation.label}
          total={images.length}
        />
      ))}
    </ol>
  );
}
