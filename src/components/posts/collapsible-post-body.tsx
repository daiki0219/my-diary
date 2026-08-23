"use client";

import { useEffect, useId, useRef, useState } from "react";

const COLLAPSED_LINE_COUNT = 4;
const OVERFLOW_TOLERANCE_PX = 1;

export function CollapsiblePostBody({
  body,
  title,
}: {
  body: string;
  title: string | null;
}) {
  const bodyId = useId();
  const bodyRef = useRef<HTMLParagraphElement>(null);
  const [canCollapse, setCanCollapse] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const toggleLabel = isExpanded ? "閉じる" : "続きを読む";
  const normalizedTitle = title?.trim();

  useEffect(() => {
    const element = bodyRef.current;

    if (!element) {
      return;
    }

    const measureOverflow = () => {
      const lineHeight = Number.parseFloat(
        window.getComputedStyle(element).lineHeight,
      );

      if (!Number.isFinite(lineHeight)) {
        return;
      }

      setCanCollapse(
        element.scrollHeight >
          lineHeight * COLLAPSED_LINE_COUNT + OVERFLOW_TOLERANCE_PX,
      );
    };

    const animationFrame = window.requestAnimationFrame(measureOverflow);

    if (typeof ResizeObserver === "undefined") {
      window.addEventListener("resize", measureOverflow);

      return () => {
        window.cancelAnimationFrame(animationFrame);
        window.removeEventListener("resize", measureOverflow);
      };
    }

    const resizeObserver = new ResizeObserver(measureOverflow);
    resizeObserver.observe(element);

    return () => {
      window.cancelAnimationFrame(animationFrame);
      resizeObserver.disconnect();
    };
  }, [body]);

  return (
    <div className="min-w-0">
      <p
        className={`mt-2.5 whitespace-pre-wrap break-words text-[15px] leading-6 text-text-secondary [overflow-wrap:anywhere] ${
          isExpanded ? "" : "line-clamp-4"
        }`}
        id={bodyId}
        ref={bodyRef}
      >
        {body}
      </p>

      {canCollapse && (
        <button
          aria-controls={bodyId}
          aria-expanded={isExpanded}
          aria-label={
            normalizedTitle
              ? `投稿「${normalizedTitle}」の本文を${toggleLabel}`
              : `この投稿の本文を${toggleLabel}`
          }
          className="-ml-1 mt-0.5 inline-flex min-h-11 items-center rounded-lg px-1 text-sm font-medium text-brand-primary-hover underline-offset-4 transition hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
          onClick={() => setIsExpanded((current) => !current)}
          type="button"
        >
          {toggleLabel}
        </button>
      )}
    </div>
  );
}
