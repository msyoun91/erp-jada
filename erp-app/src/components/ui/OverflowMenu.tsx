"use client";

import { useEffect, useRef, useState } from "react";
import { MoreHorizontal } from "lucide-react";

export function OverflowMenu({
  items,
}: {
  items: { label: string; icon: React.ReactNode; onClick: () => void; destructive?: boolean }[];
}) {
  const [abierto, setAbierto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!abierto) return;
    function onClickFuera(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setAbierto(false);
    }
    function onEscape(e: KeyboardEvent) {
      if (e.key === "Escape") setAbierto(false);
    }
    document.addEventListener("mousedown", onClickFuera);
    document.addEventListener("keydown", onEscape);
    return () => {
      document.removeEventListener("mousedown", onClickFuera);
      document.removeEventListener("keydown", onEscape);
    };
  }, [abierto]);

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        className="btn btn-ghost btn-sm"
        onClick={() => setAbierto((v) => !v)}
        aria-label="Más acciones"
        aria-expanded={abierto}
      >
        <MoreHorizontal size={14} strokeWidth={1.75} />
      </button>
      {abierto && (
        <div className="absolute right-0 z-20 mt-1 min-w-[180px] rounded-lg border border-border bg-bg-surface py-1 shadow-lg">
          {items.map((item, i) => (
            <button
              key={i}
              type="button"
              className={`flex w-full items-center gap-2 px-3 py-2 text-left t-body-m hover:bg-bg-subtle ${
                item.destructive ? "text-error" : "text-text-primary"
              }`}
              onClick={() => {
                setAbierto(false);
                item.onClick();
              }}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
