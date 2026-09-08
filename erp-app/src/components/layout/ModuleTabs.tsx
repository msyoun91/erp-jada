"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

type Tab = { codigo: string; label: string; href: string };

export function ModuleTabs({ modulo, tabs }: { modulo: string; tabs: Tab[] }) {
  const pathname = usePathname();

  if (tabs.length <= 1) return null;

  // Obras es el único módulo con páginas de detalle (/obras/{id},
  // /obras/personas/{id}): la tab activa es la del href más largo que sea
  // prefijo del pathname, porque /obras lo es de todas las demás.
  const activo = tabs.reduce<string | null>((mejor, tab) => {
    if (pathname !== tab.href && !pathname.startsWith(`${tab.href}/`)) return mejor;
    return mejor === null || tab.href.length > mejor.length ? tab.href : mejor;
  }, null);

  return (
    <div
      data-tour={`${modulo}_tabs`}
      className="mb-4 flex gap-4 overflow-x-auto border-b border-border"
    >
      {tabs.map((tab) => {
        const active = tab.href === activo;
        return (
          <Link
            key={tab.codigo}
            href={tab.href}
            aria-current={active ? "page" : undefined}
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
