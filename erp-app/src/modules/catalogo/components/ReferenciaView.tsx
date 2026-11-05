import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { FiltroDias } from "@/components/ui/FiltroDias";
import { Volver } from "@/components/ui/Volver";
import { formatMonto, type Moneda } from "@/lib/monedas";
import type { PrecioReferencia } from "../types";

// La misma versión a dos fechas: la diferencia sale de los costos, los % y el tipo de cambio. Sin aviso ni
// umbral: el gerente mira lo que más cambió.
export function ReferenciaView({ filas, dias, moneda }: { filas: PrecioReferencia[]; dias: number; moneda: Moneda }) {
  const m = (n: number | null) => (n === null ? "sin precio" : formatMonto(n, moneda));
  return (
    <div className="flex flex-col gap-4">
      <Volver href="/catalogo/paquetes">Paquetes</Volver>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="t-h3">Precios de referencia</h2>
        <FiltroDias href="/catalogo/paquetes/referencia" dias={dias} etiqueta="Comparar contra hace" />
      </div>
      <p className="t-body-m">
        El precio de cada caso de prueba de las versiones publicadas, hoy y hace {dias} días, sin IVA. Lo que más
        cambió, primero.
      </p>
      {filas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin precios para comparar</p>
          <p className="t-body-m mt-1">Aparecen cuando hay versiones publicadas con casos de prueba.</p>
        </div>
      ) : (
        <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {filas.map((f) => (
            <li key={f.caso_id} className="border-b border-border last:border-b-0">
              <Link
                href={`/catalogo/paquetes/versiones/${f.version_id}`}
                className="row tap-target flex items-center gap-3 hover:bg-bg-subtle"
              >
                <div className="min-w-0 flex-1">
                  <p className="t-body-m truncate font-medium">
                    {f.nombre} · v{f.numero} · {f.caso}
                  </p>
                  <p className="t-caption">
                    {m(f.precio_desde)} → {m(f.precio_hasta)}
                  </p>
                  {[...f.sin_precio_desde, ...f.sin_precio_hasta].length > 0 && (
                    <p className="t-caption text-error-text">
                      {[...new Set([...f.sin_precio_desde, ...f.sin_precio_hasta])].join(" · ")}
                    </p>
                  )}
                </div>
                {f.cambio !== null && (
                  <span className="t-body-m shrink-0 font-semibold">
                    {f.cambio > 0 ? "+" : ""}
                    {f.cambio.toLocaleString("es-AR", { maximumFractionDigits: 1 })} %
                  </span>
                )}
                <ChevronRight size={16} className="shrink-0 text-text-tertiary" />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
