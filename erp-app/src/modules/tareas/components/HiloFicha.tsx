import Link from "next/link";
import { formatFecha, hoyISO } from "@/lib/utils";
import { estaAbierto, estaBloqueado, estaEnEspera, estaVencido, ordenarPasos, sinReferencias } from "../derivados";
import { ESTADO_HILO, ESTADO_PASO } from "../etiquetas";
import type { HiloCompleto } from "../queries";

// La ficha del hilo al lado de otro paso: sin acciones, porque `HiloView` usa
// `?paso=` como el paso que la contiene (registro.md). `resaltado`: la ficha de un paso.
export function HiloFicha({
  hilo,
  pasos,
  sobre,
  nombres,
  yo,
  resaltado = null,
}: Pick<HiloCompleto, "hilo" | "pasos" | "sobre"> & { nombres: Record<string, string>; yo: string; resaltado?: string | null }) {
  const hoy = hoyISO();
  const nombre = (id: string | null) => (id === yo ? "Vos" : id ? (nombres[id] ?? "—") : "—");
  const activos = pasos.filter((p) => p.activo);
  const porId = new Map(activos.map((p) => [p.id, p]));

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h3 min-w-0 flex-1">{hilo.titulo}</h2>
          <span className={`badge ${ESTADO_HILO[hilo.estado].badge}`}>{ESTADO_HILO[hilo.estado].label}</span>
          <Link href={resaltado ? `/tareas/paso/${resaltado}` : `/tareas/${hilo.id}`} className="t-caption text-text-brand hover:underline">
            Abrir hilo ↗
          </Link>
        </div>
        <p className="t-caption flex flex-wrap gap-x-3">
          <span>Responsable: {nombre(hilo.responsable_id)}</span>
          {sobre && (
            <span>
              Sobre:{" "}
              <Link href={sobre.href} className="font-semibold text-text-brand hover:underline">
                {sobre.etiqueta} ↗
              </Link>
            </span>
          )}
        </p>
      </div>

      <div className="flex flex-col rounded-lg border border-border">
        {ordenarPasos(activos).map((p) => {
          const marcado = p.id === resaltado;
          return (
            <div key={p.id} className={`border-b border-border row last:border-b-0 ${marcado ? "bg-bg-subtle" : ""}`}>
              <Link href={`/tareas/paso/${p.id}`} className="flex items-center gap-3 hover:text-text-brand">
                <div className="min-w-0 flex-1">
                  <p className={`t-body-m truncate font-medium ${estaAbierto(p.estado) ? "text-text-primary" : "text-text-tertiary"}`}>
                    {p.titulo}
                  </p>
                  <p className="t-caption flex flex-wrap gap-x-3">
                    <span>{nombre(p.asignado_id ?? p.asignado_equipo_id)}</span>
                    {p.vence && <span className={estaVencido(p, hoy) ? "text-error-text" : ""}>Vence {formatFecha(p.vence)}</span>}
                    {estaBloqueado(p, porId) && <span>Espera al anterior</span>}
                    {estaEnEspera(p, hoy) && <span>En espera hasta {formatFecha(p.espera_hasta!)}</span>}
                  </p>
                </div>
                <span className={`badge ${ESTADO_PASO[p.estado].badge}`}>{ESTADO_PASO[p.estado].label}</span>
              </Link>
              {marcado && p.descripcion && <p className="t-body-m mt-2 whitespace-pre-wrap">{sinReferencias(p.descripcion)}</p>}
              {marcado && p.resultado && (
                <p className="t-body-m mt-2 whitespace-pre-wrap">
                  <span className="t-label">Resultado: </span>
                  {sinReferencias(p.resultado)}
                </p>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
