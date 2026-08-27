"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  useEffect,
  useId,
  useRef,
  useState,
  type ReactNode,
} from "react";

import { logout } from "@/app/auth/actions";
import { protectedHeaderUtilityClassName } from "@/components/layout/protected-app-navigation";
import { Button } from "@/components/ui/actions";
import { joinClassNames } from "@/components/ui/class-names";

const menuItems = [
  { href: "/profile/posts", label: "自分の日記" },
  { href: "/search", label: "検索" },
  { href: "/exchange", label: "交換日記" },
  { href: "/tags", label: "タグ" },
  { href: "/settings", label: "設定" },
] as const;

function isAdminPath(pathname: string) {
  return pathname === "/admin" || pathname.startsWith("/admin/");
}

type ProtectedMoreMenuProps = {
  children: (triggers: {
    desktopTrigger: ReactNode;
    mobileTrigger: ReactNode;
  }) => ReactNode;
};

export function ProtectedMoreMenu({ children }: ProtectedMoreMenuProps) {
  const pathname = usePathname();
  const dialogId = useId();
  const titleId = `${dialogId}-title`;
  const desktopTriggerId = `${dialogId}-desktop-trigger`;
  const mobileTriggerId = `${dialogId}-mobile-trigger`;
  const closeId = `${dialogId}-close`;
  const dialogRef = useRef<HTMLDialogElement>(null);
  const activeTriggerIdRef = useRef<string | null>(null);
  const previousOverflowRef = useRef<string | null>(null);
  const [isOpen, setIsOpen] = useState(false);
  const hasMobileBottomNavigation = !isAdminPath(pathname);

  useEffect(() => {
    return () => {
      if (previousOverflowRef.current !== null) {
        document.documentElement.style.overflow =
          previousOverflowRef.current;
      }
    };
  }, []);

  function lockDocumentScroll() {
    if (previousOverflowRef.current !== null) {
      return;
    }

    previousOverflowRef.current = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";
  }

  function unlockDocumentScroll() {
    if (previousOverflowRef.current === null) {
      return;
    }

    document.documentElement.style.overflow = previousOverflowRef.current;
    previousOverflowRef.current = null;
  }

  function openDrawer(triggerId: string) {
    const dialog = dialogRef.current;

    if (!dialog || dialog.open) {
      return;
    }

    lockDocumentScroll();
    dialog.showModal();
    activeTriggerIdRef.current = triggerId;
    setIsOpen(true);
    requestAnimationFrame(() => {
      document.getElementById(closeId)?.focus();
    });
  }

  function closeDrawer() {
    dialogRef.current?.close();
  }

  const desktopTrigger = (
    <button
      aria-controls={dialogId}
      aria-expanded={isOpen}
      aria-haspopup="dialog"
      aria-label="その他のメニューを開く"
      className={joinClassNames(
        protectedHeaderUtilityClassName,
        isOpen && "bg-brand-soft text-brand-primary-hover",
      )}
      id={desktopTriggerId}
      onClick={() => openDrawer(desktopTriggerId)}
      type="button"
    >
      <svg
        aria-hidden="true"
        className="size-6"
        fill="none"
        focusable="false"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.8"
        viewBox="0 0 24 24"
      >
        <path d="M5 7h14M5 12h14M5 17h14" />
      </svg>
    </button>
  );

  const mobileTrigger = (
    <>
      <div aria-hidden="true" className="h-16 shrink-0 lg:hidden" />
      <Button
        aria-controls={dialogId}
        aria-expanded={isOpen}
        aria-haspopup="dialog"
        aria-label="その他のメニューを開く"
        className={joinClassNames(
          "fixed right-3 z-30 gap-2 border border-border-subtle bg-surface-elevated/95 px-3 text-sm shadow-surface hover:bg-surface-muted sm:right-4 lg:hidden",
          hasMobileBottomNavigation
            ? "bottom-[calc(53px+env(safe-area-inset-bottom)+0.75rem)]"
            : "bottom-[calc(env(safe-area-inset-bottom)+0.75rem)]",
        )}
        id={mobileTriggerId}
        onClick={() => openDrawer(mobileTriggerId)}
        type="button"
        variant="quiet"
      >
        <svg
          aria-hidden="true"
          className="size-5"
          fill="currentColor"
          focusable="false"
          viewBox="0 0 24 24"
        >
          <circle cx="5" cy="12" r="1.6" />
          <circle cx="12" cy="12" r="1.6" />
          <circle cx="19" cy="12" r="1.6" />
        </svg>
        <span>その他</span>
      </Button>
    </>
  );

  return (
    <>
      {children({ desktopTrigger, mobileTrigger })}

      <dialog
        aria-labelledby={titleId}
        className="fixed inset-0 m-0 h-dvh max-h-none w-full max-w-none overflow-hidden border-0 bg-transparent p-0 text-text-primary"
        data-more-drawer=""
        id={dialogId}
        onClick={(event) => {
          if (event.target === event.currentTarget) {
            closeDrawer();
          }
        }}
        onClose={() => {
          setIsOpen(false);
          unlockDocumentScroll();
          const triggerId = activeTriggerIdRef.current;
          activeTriggerIdRef.current = null;
          requestAnimationFrame(() => {
            if (triggerId) {
              document.getElementById(triggerId)?.focus();
            }
          });
        }}
        ref={dialogRef}
      >
        <div
          className="ml-auto flex h-dvh w-[86vw] max-w-96 flex-col overflow-y-auto overscroll-contain border-l border-border-subtle bg-surface-elevated shadow-surface"
          data-more-drawer-panel=""
        >
          <div className="sticky top-0 z-10 flex items-center justify-between gap-4 border-b border-border-subtle/70 bg-surface-elevated/95 px-5 py-4 backdrop-blur-sm">
            <h2
              className="min-w-0 font-brand text-2xl font-medium tracking-wide text-text-primary"
              id={titleId}
            >
              その他
            </h2>
            <Button
              aria-label="メニューを閉じる"
              className="shrink-0 gap-1.5 px-3 text-sm"
              id={closeId}
              onClick={closeDrawer}
              type="button"
              variant="quiet"
            >
              <svg
                aria-hidden="true"
                className="size-5"
                fill="none"
                focusable="false"
                stroke="currentColor"
                strokeLinecap="round"
                strokeWidth="1.8"
                viewBox="0 0 24 24"
              >
                <path d="m6 6 12 12M18 6 6 18" />
              </svg>
              <span>閉じる</span>
            </Button>
          </div>

          <nav aria-label="その他のメニュー" className="px-4 py-5">
            <ul className="space-y-1">
              {menuItems.map((item) => (
                <li key={item.href}>
                  <Link
                    className="flex min-h-12 min-w-0 items-center rounded-control px-4 py-3 font-medium leading-6 text-text-secondary transition hover:bg-surface-muted hover:text-text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
                    href={item.href}
                    onClick={closeDrawer}
                  >
                    <span className="min-w-0 break-words [overflow-wrap:anywhere]">
                      {item.label}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          </nav>

          <form
            action={logout}
            className="mt-auto border-t border-border-subtle px-4 pt-5 pb-[calc(1.25rem+env(safe-area-inset-bottom))]"
            onSubmit={closeDrawer}
          >
            <Button className="w-full" type="submit" variant="quiet">
              ログアウト
            </Button>
          </form>
        </div>
      </dialog>
    </>
  );
}
