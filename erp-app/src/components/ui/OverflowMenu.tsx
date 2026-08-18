"use client";

import { useEffect, useRef, useState } from "react";
import { MoreHorizontal } from "lucide-react";

export function OverflowMenu({
  items,
}: {
  items: { label: string; icon: React.ReactNode; onClick: () => void; destructive?: boolean }[];
}) {
  const [pos, setPos] = useState<{ top: number; right: number } | null>(null);
  const abierto = pos !== null;
  const ref = useRef<HTMLDivElement>(null);
  const botonRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!abierto) return;
    function onClickFuera(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setPos(null);
    }
    function onEscape(e: KeyboardEvent) {
      if (e.key === "Escape") setPos(null);
    }
    // El menú es `fixed` (para no quedar recortado por el scroll del panel),
    // así que si el contenedor scrollea se despega del botón — se cierra.
    function onScroll() {
      setPos(null);
    }
    document.addEventListener("mousedown", onClickFuera);
    document.addEventListener("keydown", onEscape);
    document.addEventListener("scroll", onScroll, true);
    return () => {
      document.removeEventListener("mousedown", onClickFuera);
      document.removeEventListener("keydown", onEscape);
      document.removeEventListener("scroll", onScroll, true);
    };
  }, [abierto]);

  // Posición calculada al abrir en vez de `absolute`: dentro de un panel con
  // overflow-y-auto un menú absoluto queda recortado por el contenedor.
  function alternar() {
    if (abierto) {
      setPos(null);
      return;
    }
    const r = botonRef.current!.getBoundingClientRect();
    // ponytail: alto estimado (~38px por ítem) solo para decidir si abre hacia
    // arriba; si algún día los ítems cambian de alto, medir después de montar.
    const alto = items.length * 38 + 8;
    const cabeAbajo = window.innerHeight - r.bottom > alto;
    setPos({
      top: cabeAbajo ? r.bottom + 4 : Math.max(4, r.top - alto - 4),
      right: window.innerWidth - r.right,
    });
  }

  return (
    <div className="relative" ref={ref}>
      <button
        ref={botonRef}
        type="button"
        className="btn btn-ghost btn-sm"
        onClick={alternar}
        aria-label="Más acciones"
        aria-expanded={abierto}
      >
        <MoreHorizontal size={14} strokeWidth={1.75} />
      </button>
      {pos && (
        <div
          style={{ top: pos.top, right: pos.right }}
          className="fixed z-20 min-w-[180px] rounded-lg border border-border bg-bg-surface py-1 shadow-lg"
        >
          {items.map((item, i) => (
            <button
              key={i}
              type="button"
              className={`flex w-full items-center gap-2 px-3 py-2 text-left t-body-m hover:bg-bg-subtle ${
                item.destructive ? "text-error" : "text-text-primary"
              }`}
              onClick={() => {
                setPos(null);
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
