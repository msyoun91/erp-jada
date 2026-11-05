"use client";

import { useState } from "react";
import { SlidersHorizontal } from "lucide-react";

// La fila de buscador y filtros. En el celular, los filtros van plegados detrás de un botón que
// cuenta los que están puestos: con cuatro, Insumos eran cuatro filas antes del primer insumo.
// Desde `sm` el plegado no existe (`sm:contents`) y todo queda en la misma fila, como antes.
// Para dos filtros o más: con uno solo, esconderlo cuesta un toque y no ahorra lugar.
export function Filtros({
  buscador,
  activos,
  children,
}: {
  buscador: React.ReactNode;
  activos: number;
  children: React.ReactNode;
}) {
  const [abierto, setAbierto] = useState(false);

  return (
    <div className="flex flex-wrap items-center gap-3">
      <div className="flex basis-full items-center gap-3 sm:contents">
        {buscador}
        <button
          type="button"
          className="btn btn-secondary shrink-0 sm:hidden"
          onClick={() => setAbierto(!abierto)}
          aria-expanded={abierto}
        >
          <SlidersHorizontal size={16} />
          Filtros
          {activos > 0 && <span className="badge badge-brand">{activos}</span>}
        </button>
      </div>
      <div className={`${abierto ? "flex" : "hidden"} basis-full flex-wrap items-center gap-3 sm:contents`}>
        {children}
      </div>
    </div>
  );
}
