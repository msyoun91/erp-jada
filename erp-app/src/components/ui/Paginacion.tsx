"use client";

import { useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";

const POR_PAGINA = 20;

export function usePaginado<T>(items: T[]) {
  const [pagina, setPagina] = useState(0);
  const totalPaginas = Math.max(1, Math.ceil(items.length / POR_PAGINA));
  // Filtrar puede dejar `pagina` fuera de rango: se ajusta durante el render, no en un efecto.
  const actual = Math.min(pagina, totalPaginas - 1);

  return {
    visibles: items.slice(actual * POR_PAGINA, actual * POR_PAGINA + POR_PAGINA),
    pagina: actual,
    setPagina,
    total: items.length,
    totalPaginas,
  };
}

// Las etiquetas son sustantivo + adjetivo en plural ("tareas completadas"), así
// que el singular se arma sacando la s final de cada palabra.
function singular(etiqueta: string) {
  return etiqueta.replace(/s\b/g, "");
}

// El contador de total va siempre; los botones, solo con más de una página.
// Las props de paginado son opcionales para el listado que muestra el total sin
// paginar (la Lista de tareas): el contador de las cuatro tabs del módulo sale
// del mismo componente, a la misma altura y alineación.
export function Paginacion({
  pagina = 0,
  setPagina,
  total,
  totalPaginas = 1,
  etiqueta,
}: {
  pagina?: number;
  setPagina?: (pagina: number) => void;
  total: number;
  totalPaginas?: number;
  etiqueta: string;
}) {
  return (
    <div className="mb-2 flex items-center justify-between gap-3">
      <p className="t-caption">
        {total} {total === 1 ? singular(etiqueta) : etiqueta}
      </p>

      {totalPaginas > 1 && setPagina && (
        <div className="flex shrink-0 items-center gap-2">
          <button
            className="btn btn-secondary px-2"
            onClick={() => setPagina(pagina - 1)}
            disabled={pagina === 0}
            aria-label="Página anterior"
          >
            <ChevronLeft size={16} strokeWidth={1.75} />
          </button>
          <span className="t-caption">
            {pagina + 1} / {totalPaginas}
          </span>
          <button
            className="btn btn-secondary px-2"
            onClick={() => setPagina(pagina + 1)}
            disabled={pagina >= totalPaginas - 1}
            aria-label="Página siguiente"
          >
            <ChevronRight size={16} strokeWidth={1.75} />
          </button>
        </div>
      )}
    </div>
  );
}
