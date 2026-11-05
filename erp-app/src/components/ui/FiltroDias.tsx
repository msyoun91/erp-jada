import Link from "next/link";

// El período de los logs: escrito cuatro veces entre Pendientes y Auditoría,
// con el activo en `btn-primary` — navy sólido, que en el sistema es un botón
// de acción, no un filtro elegido. Es un `.segmented` de links.
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
    <div className="segmented" role="group" aria-label={etiqueta}>
      {DIAS_OPCIONES.map((d) => (
        <Link
          key={d}
          href={`${href}${href.includes("?") ? "&" : "?"}dias=${d}`}
          aria-current={d === dias ? "page" : undefined}
          className="segmented-item tap-target"
        >
          {d} días
        </Link>
      ))}
    </div>
  );
}
