"use client";

// Cara común de las tres entidades del módulo: hilo, tarea y proyecto se ven
// igual en cualquier listado — título clickeable, badges a la derecha y una
// fila de métricas debajo. La isla no tiene acciones propias: todo lo que se
// hace sobre la entidad vive en su panel derecho, que abre este click.
export function Isla({
  titulo,
  badges,
  meta,
  atenuada,
  onAbrir,
  children,
}: {
  titulo: string;
  badges?: React.ReactNode;
  meta?: React.ReactNode;
  atenuada?: boolean;
  onAbrir: () => void;
  // Contenido anidado dentro de la isla — hoy solo los pasos de un hilo.
  children?: React.ReactNode;
}) {
  return (
    <div className={`rounded-lg border border-border bg-bg-surface ${atenuada ? "opacity-60" : ""}`}>
      <button
        className="flex w-full flex-wrap items-center gap-2 p-[13px] px-5 text-left"
        onClick={onAbrir}
      >
        <p className="t-body-m min-w-0 flex-1 truncate font-semibold text-text-primary">{titulo}</p>
        {badges}
      </button>

      {meta && <div className="t-caption flex flex-wrap items-center gap-3 px-5 pb-3">{meta}</div>}

      {children}
    </div>
  );
}
