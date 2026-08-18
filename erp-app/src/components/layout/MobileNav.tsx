"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import { Menu, X } from "lucide-react";
import { usePathname } from "next/navigation";
import { SidebarNav } from "./SidebarNav";

export function MobileNav({
  modulosVisibles,
  nombre,
}: {
  modulosVisibles: string[];
  nombre: string;
}) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  return (
    <>
      <div className="flex h-14 items-center gap-3 border-b border-border bg-bg-nav px-4 md:hidden">
        <button
          onClick={() => setOpen(true)}
          className="flex h-11 w-11 items-center justify-center rounded-sm text-text-tertiary hover:bg-bg-subtle"
          aria-label="Abrir menú"
        >
          <Menu size={18} strokeWidth={1.75} />
        </button>
        <Image src="/logo.svg" alt="JADA" width={60} height={22} className="logo" priority />
      </div>

      {open && (
        <div className="fixed inset-0 z-40 bg-black/40 md:hidden" onClick={() => setOpen(false)} />
      )}

      <div
        className={`fixed top-0 left-0 z-50 flex h-screen w-[220px] flex-col border-r border-border bg-bg-nav p-3 transition-transform duration-200 md:hidden ${
          open ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        <div className="mb-4 ml-1 flex items-center justify-between">
          <Image src="/logo.svg" alt="JADA" width={72} height={26} className="logo" priority />
          <button
            onClick={() => setOpen(false)}
            className="flex h-11 w-11 items-center justify-center rounded-sm text-text-tertiary hover:bg-bg-subtle"
            aria-label="Cerrar menú"
          >
            <X size={14} strokeWidth={1.75} />
          </button>
        </div>
        <SidebarNav modulosVisibles={modulosVisibles} nombre={nombre} />
      </div>
    </>
  );
}
