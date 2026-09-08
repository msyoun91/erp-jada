"use client";

import { useState } from "react";
import { ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { FiltroDias } from "@/components/ui/FiltroDias";
import { formatFechaHora } from "@/lib/utils";
import { resolverPendiente, similaresDelPendiente } from "../actions";
import {
  LABEL_TIPO_PENDIENTE,
  type HistorialAprobacion,
  type Pendiente,
  type SimilarPendiente,
} from "../types";

// Solo las tres altas tienen contra qué compararse; los dos vínculos esperan
// por dueño ajeno, no por parecido.
const TIENE_SIMILARES = new Set(["obra", "empresa", "persona"]);

export function PendientesView({
  pendientes,
  historial,
  dias,
  puedeAprobar,
}: {
  pendientes: Pendiente[];
  historial: HistorialAprobacion[];
  dias: number;
  puedeAprobar: boolean;
}) {
  const [similares, setSimilares] = useState<Record<string, SimilarPendiente[]>>({});
  const [rechazando, setRechazando] = useState<string>();
  const [motivo, setMotivo] = useState("");
  // Cuál se está resolviendo, no si hay alguna: como booleano, aprobar una fila
  // deshabilitaba el botón de todas sin decir cuál estaba procesando.
  const [enviando, setEnviando] = useState<string>();

  async function verSimilares(p: Pendiente) {
    const encontrados = await similaresDelPendiente(p.tipo, p.registro_id);
    setSimilares((prev) => ({ ...prev, [p.registro_id]: encontrados }));
  }

  async function resolver(p: Pendiente, aprobar: boolean) {
    setEnviando(p.registro_id);
    const result = await resolverPendiente({
      tipo: p.tipo,
      registro_id: p.registro_id,
      aprobar,
      motivo: aprobar ? "" : motivo,
    });
    setEnviando(undefined);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(aprobar ? "Aprobada" : "Rechazada");
    setRechazando(undefined);
    setMotivo("");
  }

  return (
    <div className="flex flex-col gap-6">
      <section className="card p-4">
        <h2 className="t-h3 mb-1 flex items-center gap-2">
          <ShieldCheck size={18} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          Esperando autorización
        </h2>
        <p className="t-body-m mb-3 max-w-prose">
          Un alta que se parece a algo ya cargado, o un vínculo con una persona o empresa de otro
          usuario, queda congelado acá: existe, pero no participa de ninguna obra ni la ve nadie más
          hasta que se resuelva.
        </p>

        {pendientes.length === 0 ? (
          <div className="empty-state">
            <p className="t-h3">No hay nada esperando</p>
            <p className="t-body-m mt-1">Toda alta y todo vínculo del módulo están resueltos.</p>
          </div>
        ) : (
          // Filas separadas por borde, no cards adentro de una card: las dos
          // eran `bg-bg-surface` y la interna se distinguía solo por su borde.
          <ul className="flex flex-col">
            {pendientes.map((p) => {
              const parecidos = similares[p.registro_id];
              const procesando = enviando === p.registro_id;
              return (
                <li
                  key={p.registro_id}
                  className="flex flex-col gap-2 border-b border-border py-3 first:pt-0 last:border-b-0 last:pb-0"
                >
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <span className="flex w-full min-w-0 items-center gap-2 sm:w-auto sm:flex-1">
                      <span className="badge badge-warning shrink-0">
                        {LABEL_TIPO_PENDIENTE[p.tipo]}
                      </span>
                      <span className="t-body-m truncate font-semibold text-text-primary">
                        {p.etiqueta}
                      </span>
                    </span>
                    <span className="t-caption">{p.solicitante}</span>
                    <span className="t-caption">{formatFechaHora(p.created_at)}</span>
                  </div>

                  <p className="t-caption">{p.motivo}</p>

                  {parecidos && parecidos.length > 0 && (
                    <ul className="t-caption flex flex-col gap-1 border-l-2 border-border pl-2">
                      {parecidos.map((s, i) => (
                        <li key={`${s.etiqueta}-${i}`}>
                          <span className="font-semibold">{s.etiqueta}</span>
                          {s.detalle && ` · ${s.detalle}`}
                        </li>
                      ))}
                    </ul>
                  )}
                  {parecidos && parecidos.length === 0 && (
                    <p className="t-caption">Ya no hay ninguna parecida activa.</p>
                  )}

                  {puedeAprobar && rechazando === p.registro_id ? (
                    <div className="flex flex-col gap-2">
                      <textarea
                        rows={2}
                        className="input"
                        placeholder="Motivo del rechazo — es lo único que va a leer quien la cargó"
                        aria-label="Motivo del rechazo"
                        value={motivo}
                        onChange={(e) => setMotivo(e.target.value)}
                      />
                      <div className="flex flex-wrap gap-2">
                        <button
                          className="btn btn-danger btn-sm"
                          disabled={procesando || !motivo.trim()}
                          onClick={() => resolver(p, false)}
                        >
                          {procesando ? "Rechazando…" : "Confirmar rechazo"}
                        </button>
                        <button
                          className="btn btn-ghost btn-sm"
                          onClick={() => {
                            setRechazando(undefined);
                            setMotivo("");
                          }}
                        >
                          Cancelar
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div className="flex flex-wrap gap-2">
                      {puedeAprobar && TIENE_SIMILARES.has(p.tipo) && !parecidos && (
                        <button className="btn btn-ghost btn-sm" onClick={() => verSimilares(p)}>
                          Ver a qué se parece
                        </button>
                      )}
                      {puedeAprobar && (
                        <>
                          <button
                            className="btn btn-primary btn-sm"
                            disabled={procesando}
                            onClick={() => resolver(p, true)}
                          >
                            {procesando ? "Aprobando…" : "Aprobar"}
                          </button>
                          <button
                            className="btn btn-secondary btn-sm"
                            onClick={() => {
                              setRechazando(p.registro_id);
                              setMotivo("");
                            }}
                          >
                            Rechazar
                          </button>
                        </>
                      )}
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}

        {!puedeAprobar && pendientes.length > 0 && (
          <p className="t-caption mt-3">
            Ves la cola pero no podés resolverla: eso necesita el permiso de aprobar.
          </p>
        )}
      </section>

      <section className="card p-4">
        <div className="mb-1 flex flex-wrap items-center gap-3">
          <h2 className="t-h3 flex-1">Ya resueltas</h2>
          {/* Adentro de la card y no arriba de la página: el período acota solo
              esta lista, no la cola de arriba. */}
          <FiltroDias href="/obras/pendientes" dias={dias} etiqueta="Período de lo resuelto" />
        </div>
        <p className="t-body-m mb-3 max-w-prose">
          Quién resolvió qué y con qué motivo. Sin esto, un rechazo es una fila que desapareció.
        </p>

        {historial.length === 0 ? (
          <div className="empty-state">
            <p className="t-h3">Nada resuelto</p>
            <p className="t-body-m mt-1">Nadie aprobó ni rechazó en este período.</p>
          </div>
        ) : (
          <ul className="flex flex-col">
            {historial.map((h) => (
              <li
                key={h.aprobacion_id}
                className="flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-border py-3 first:pt-0 last:border-b-0 last:pb-0"
              >
                <span className="t-caption">{formatFechaHora(h.created_at)}</span>
                <span className={`badge ${h.aprobada ? "badge-success" : "badge-error"}`}>
                  {h.aprobada ? "Aprobada" : "Rechazada"}
                </span>
                <span className="t-body-m min-w-0 basis-full truncate font-semibold text-text-primary sm:basis-0 sm:grow">
                  {h.etiqueta}
                </span>
                <span className="t-caption">{LABEL_TIPO_PENDIENTE[h.tipo]}</span>
                <span className="t-caption">{h.decidido_por}</span>
                {h.motivo && <span className="t-caption">— {h.motivo}</span>}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
