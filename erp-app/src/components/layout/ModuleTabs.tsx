"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

type Tab = { codigo: string; label: string; href: string };

export function ModuleTabs({ modulo, tabs }: { modulo: string; tabs: Tab[] }) {
  const pathname = usePathname();

  if (tabs.length <= 1) return null;

  return (
    <div
      data-tour={`${modulo}_tabs`}
      className="mb-4 flex gap-4 overflow-x-auto border-b border-border"
    >
      {tabs.map((tab) => {
        const active = pathname === tab.href;
        return (
          <Link
            key={tab.codigo}
            href={tab.href}
            className={`t-body-m shrink-0 px-1 pb-2 font-medium ${
              active
                ? "border-b-2 border-brand-500 text-text-brand"
                : "text-text-tertiary"
            }`}
          >
            {tab.label}
          </Link>
        );
      })}
    </div>
  );
}
