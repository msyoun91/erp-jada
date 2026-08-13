"use client";

import { UsersRound, type LucideIcon } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

export const ICON_MAP: Record<string, LucideIcon> = {
  usuarios: UsersRound,
};

export const LABEL_MAP: Record<string, string> = {
  usuarios: "Usuarios",
};

type NavItem = { modulo: string; href: string };

const NAV_ITEMS: NavItem[] = [{ modulo: "usuarios", href: "/usuarios" }];

export function SidebarNav({ modulosVisibles }: { modulosVisibles: string[] }) {
  const pathname = usePathname();
  const items = NAV_ITEMS.filter((item) => modulosVisibles.includes(item.modulo));

  return (
    <nav className="flex flex-row gap-1 overflow-x-auto border-b border-border bg-bg-nav p-2 lg:h-full lg:w-[168px] lg:flex-col lg:overflow-visible lg:border-b-0 lg:border-r lg:p-3">
      {items.map(({ modulo, href }) => {
        const Icon = ICON_MAP[modulo];
        const active = pathname.startsWith(href);
        return (
          <Link
            key={modulo}
            href={href}
            className={`nav-item shrink-0 ${active ? "nav-item-active" : ""}`}
          >
            <Icon size={16} strokeWidth={1.75} />
            {LABEL_MAP[modulo]}
          </Link>
        );
      })}
    </nav>
  );
}
