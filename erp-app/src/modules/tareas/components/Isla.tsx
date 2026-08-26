"use client";

import { ChevronRight } from "lucide-react";

// Cara común de las tres entidades del módulo: hilo, tarea y proyecto se ven
// igual en cualquier listado — título clickeable, badges a la derecha y una
// fila de métricas debajo. La isla no tiene acciones propias: todo lo que se
// hace sobre la entidad vive en su panel derecho, que abre este click.
export function Isla({
  titulo,
  badges,
  meta,
  atenuada,
  barra,
  grande,
  onAbrir,
  children,
}: {
  titulo: string;
  badges?: React.ReactNode;
  meta?: React.ReactNode;
  atenuada?: boolean;
  // Clase de fondo de la barra izquierda de 3px. Solo la tarea la pasa: es su
  // temperatura la que ordena la lista, y hilo y proyecto no tienen una.
  barra?: string;
  // Una sola isla en pantalla (Misión): mismo componente con aire, no una
  // segunda cara de la tarea para mantener sincronizada.
  grande?: boolean;
  onAbrir: () => void;
  // Contenido anidado dentro de la isla — hoy solo los pasos de un hilo.
  children?: React.ReactNode;
}) {
  return (
    <div
      className={`relative overflow-hidden rounded-lg border border-border ${
        // Atenuar con color y no con `opacity`: la opacidad baja el contraste
        // de todo junto y dejaba el texto de una tarea terminada abajo de AA.
        atenuada ? "bg-bg-subtle" : "bg-bg-surface"
      }`}
    >
      {barra && <span aria-hidden className={`absolute inset-y-0 left-0 w-[3px] ${barra}`} />}

      <button
        className={`flex w-full flex-wrap items-center gap-2 text-left ${grande ? "px-6 py-5" : "row"}`}
        onClick={onAbrir}
      >
        <span
          className={`min-w-0 flex-1 font-semibold ${
            grande ? "t-h2" : "t-body-m truncate"
          } ${atenuada ? "text-text-tertiary" : "text-text-primary"}`}
        >
          {titulo}
        </span>
        {badges}
        {/* Indicio permanente de que la isla abre algo: en touch no hay hover
            del que colgar la única señal de affordance. */}
        <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
      </button>

      {meta && (
        <div
          className={`t-caption flex flex-wrap items-center gap-3 ${grande ? "px-6 pb-5" : "px-5 pb-3"}`}
        >
          {meta}
        </div>
      )}

      {children}
    </div>
  );
}
