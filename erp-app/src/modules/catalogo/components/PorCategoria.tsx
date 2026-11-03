"use client";

import { ChevronRight } from "lucide-react";
import { usePaginado } from "@/components/ui/Paginacion";

type Grupo<T> = { id: string | null; nombre: string | null; total: number; items: T[] };

// El toggle "Agrupar por categoría" de las listas del catálogo. Ordena por categoría antes de paginar, así una
// página corta un grupo como mucho en sus bordes; dentro de cada una queda el orden que traía (el sort es estable).
export function usePaginadoPorCategoria<T>(
  items: T[],
  categoriaDe: (x: T) => string,
  nombreCategoria: Map<string, string>,
  agrupar: boolean,
) {
  const nombre = (id: string) => nombreCategoria.get(id) ?? "Sin categoría";
  const ordenados = agrupar
    ? [...items].sort((a, b) => nombre(categoriaDe(a)).localeCompare(nombre(categoriaDe(b))))
    : items;
  const { visibles, ...paginado } = usePaginado(ordenados);

  const total = new Map<string, number>();
  for (const x of ordenados) total.set(categoriaDe(x), (total.get(categoriaDe(x)) ?? 0) + 1);

  const grupos: Grupo<T>[] = [];
  for (const x of visibles) {
    const id = agrupar ? categoriaDe(x) : null;
    const ultimo = grupos.at(-1);
    if (ultimo && ultimo.id === id) ultimo.items.push(x);
    else grupos.push({ id, nombre: id && nombre(id), total: id ? (total.get(id) ?? 0) : visibles.length, items: [x] });
  }
  return { grupos, paginado };
}

// Sin agrupar es una sola lista; agrupada, un plegable por categoría con su total (el de todas las páginas).
export function ListaPorCategoria<T>({ grupos, fila }: { grupos: Grupo<T>[]; fila: (x: T) => React.ReactNode }) {
  return (
    <div className="flex flex-col gap-3">
      {grupos.map((g) => {
        const lista = (
          <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">{g.items.map(fila)}</ul>
        );
        return g.nombre === null ? (
          <div key="todos">{lista}</div>
        ) : (
          <details key={g.id} open className="group">
            {/* Flex y no el triángulo nativo: con `display: list-item` el texto quedaba arriba de los 44px de mobile. */}
            <summary className="tap-target flex cursor-pointer list-none items-center gap-1 [&::-webkit-details-marker]:hidden">
              <ChevronRight
                size={14}
                strokeWidth={1.75}
                className="shrink-0 text-text-tertiary transition-transform group-open:rotate-90"
              />
              <span className="t-label">
                {g.nombre} ({g.total})
              </span>
            </summary>
            <div className="mt-1">{lista}</div>
          </details>
        );
      })}
    </div>
  );
}
