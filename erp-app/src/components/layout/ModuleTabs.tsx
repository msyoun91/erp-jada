"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export type Tab = { codigo: string; label: string; href: string };

// Obras es el único módulo con páginas de detalle (/obras/{id},
// /obras/personas/{id}): la tab activa es la del href más largo que sea
// prefijo del pathname, porque /obras lo es de todas las demás.
// Compartida con Breadcrumb — misma noción de "dónde estoy".
export function tabActiva(pathname: string, tabs: Tab[]): string | null {
  return tabs.reduce<string | null>((mejor, tab) => {
    if (pathname !== tab.href && !pathname.startsWith(`${tab.href}/`)) return mejor;
    return mejor === null || tab.href.length > mejor.length ? tab.href : mejor;
  }, null);
}

export function ModuleTabs({ modulo, tabs }: { modulo: string; tabs: Tab[] }) {
  const pathname = usePathname();

  if (tabs.length <= 1) return null;

  const activo = tabActiva(pathname, tabs);

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
