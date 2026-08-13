"use client";

import { Home, UsersRound, ListTodo, LogOut, type LucideIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { signOutAction } from "@/modules/auth/actions";

export const ICON_MAP: Record<string, LucideIcon> = {
  dashboard: Home,
  usuarios: UsersRound,
  tareas: ListTodo,
};

export const LABEL_MAP: Record<string, string> = {
  dashboard: "Inicio",
  usuarios: "Usuarios",
  tareas: "Tareas",
};

type NavItem = { modulo: string; href: string };

const NAV_ITEM_INICIO: NavItem = { modulo: "dashboard", href: "/" };
const NAV_ITEMS: NavItem[] = [
  { modulo: "usuarios", href: "/usuarios" },
  { modulo: "tareas", href: "/tareas" },
];

function initials(nombre: string) {
  const parts = nombre.trim().split(" ");
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return nombre.slice(0, 2).toUpperCase();
}

export function SidebarNav({
  modulosVisibles,
  nombre,
}: {
  modulosVisibles: string[];
  nombre: string;
}) {
  const pathname = usePathname();
  const items = [
    NAV_ITEM_INICIO,
    ...NAV_ITEMS.filter((item) => modulosVisibles.includes(item.modulo)),
  ];

  return (
    <div className="flex flex-1 flex-col">
      <nav className="flex flex-1 flex-col gap-1">
        {items.map(({ modulo, href }) => {
          const Icon = ICON_MAP[modulo];
          const active = href === "/" ? pathname === "/" : pathname.startsWith(href);
          return (
            <Link key={modulo} href={href} className={`nav-item ${active ? "nav-item-active" : ""}`}>
              <Icon size={16} strokeWidth={1.75} />
              {LABEL_MAP[modulo]}
            </Link>
          );
        })}
      </nav>

      <div className="mt-2 flex items-center gap-2 border-t border-border pt-2">
        <div className="flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-full bg-brand-900 text-[13px] font-semibold text-white">
          {initials(nombre)}
        </div>
        <span className="t-body-m flex-1 truncate text-[13px] font-semibold text-text-primary">
          {nombre}
        </span>
        <form action={signOutAction}>
          <button
            type="submit"
            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-sm text-text-tertiary hover:bg-bg-subtle hover:text-text-secondary"
            title="Cerrar sesión"
          >
            <LogOut size={14} strokeWidth={1.75} />
          </button>
        </form>
      </div>
    </div>
  );
}
