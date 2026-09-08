import Link from "next/link";

// El período de los logs: escrito cuatro veces entre Pendientes y Auditoría,
// con el activo en `btn-primary` — navy sólido, que en el sistema es un botón
// de acción, no un filtro elegido. Misma forma que el segmented de relación de
// la Lista de tareas.
export const DIAS_OPCIONES = [7, 30, 90];

export function FiltroDias({
  href,
  dias,
  etiqueta,
}: {
  href: string;
  dias: number;
  etiqueta: string;
}) {
  return (
    <div className="flex rounded-lg border border-border p-0.5" role="group" aria-label={etiqueta}>
      {DIAS_OPCIONES.map((d) => (
        <Link
          key={d}
          href={`${href}?dias=${d}`}
          aria-current={d === dias ? "page" : undefined}
          className={`tap-target t-caption flex items-center rounded-md px-3 py-1 ${
            d === dias ? "bg-brand-50 font-semibold text-brand-700" : "text-text-tertiary"
          }`}
        >
          {d} días
        </Link>
      ))}
    </div>
  );
}
