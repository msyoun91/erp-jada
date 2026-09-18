import { AlertTriangle, Ban } from "lucide-react";

// Las dos caras de la misma columna: esperando (`pendiente`) y rechazada
// (`motivo_rechazo` con la fila ya desactivada). Se muestra en la ficha porque
// es donde va a mirar quien la cargó cuando no entienda por qué su alta no
// aparece en ningún lado.
export function EstadoPendiente({
  pendiente,
  motivoRechazo,
  queEs,
  detalle,
}: {
  pendiente: boolean;
  motivoRechazo: string | null;
  queEs: string;
  detalle: string;
}) {
  if (!pendiente && !motivoRechazo) return null;

  if (pendiente) {
    return (
      <div className="flex gap-2 rounded-md border border-warning/20 bg-warning-bg px-3 py-2 text-warning-text">
        <AlertTriangle size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
        {/* El color va repuesto en cada hijo: `.t-body-m` y `.t-caption` traen
            el suyo (`text-text-secondary` / `text-text-tertiary`) y le ganan
            por especificidad al `text-warning-text` heredado del contenedor.
            En dark eso dejaba el detalle en ~4:1 sobre el fondo del aviso. */}
        <div className="min-w-0 flex-1">
          <p className="t-body-m font-semibold text-warning-text">
            {queEs} está pendiente de autorización
          </p>
          <p className="t-caption mt-0.5 text-warning-text">{detalle}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex gap-2 rounded-md border border-error/20 bg-error-bg px-3 py-2 text-error-text">
      <Ban size={16} strokeWidth={1.75} className="mt-0.5 shrink-0" />
      <div className="min-w-0 flex-1">
        <p className="t-body-m font-semibold text-error-text">{queEs} fue rechazada</p>
        <p className="t-caption mt-0.5 text-error-text">{motivoRechazo}</p>
      </div>
    </div>
  );
}
