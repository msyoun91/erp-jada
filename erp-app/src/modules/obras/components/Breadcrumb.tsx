import Link from "next/link";

// Encabezado de las tres fichas: `Personas / Juan Pérez`. Reemplaza al botón
// "← Personas", que era navegación disfrazada de acción — con `btn-ghost`
// pesaba lo mismo que "Editar", al lado del nombre de lo que se está mirando.
// El nombre no se repite en una línea aparte: la ruta y el título son la misma
// línea, y el `t-h2` sigue siendo el elemento dominante.
export function Breadcrumb({
  padre,
  href,
  actual,
}: {
  padre: string;
  href: string;
  actual: string;
}) {
  return (
    <div className="flex min-w-0 flex-1 items-center gap-1.5">
      <Link
        href={href}
        className="t-caption tap-target flex shrink-0 items-center hover:text-text-brand"
      >
        {padre}
      </Link>
      <span className="t-caption shrink-0" aria-hidden>
        /
      </span>
      <h2 className="t-h2 min-w-0 flex-1 truncate">{actual}</h2>
    </div>
  );
}
