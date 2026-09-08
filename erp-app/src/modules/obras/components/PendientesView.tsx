"use client";

import { useState } from "react";
import Link from "next/link";
import { ShieldCheck } from "lucide-react";
import { toast } from "sonner";
import { formatFechaHora } from "@/lib/utils";
import { resolverPendiente, similaresDelPendiente } from "../actions";
import {
  LABEL_TIPO_PENDIENTE,
  type HistorialAprobacion,
  type Pendiente,
  type SimilarPendiente,
} from "../types";

const DIAS_OPCIONES = [7, 30, 90];

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
  const [enviando, setEnviando] = useState(false);

  async function verSimilares(p: Pendiente) {
    const encontrados = await similaresDelPendiente(p.tipo, p.registro_id);
    setSimilares((prev) => ({ ...prev, [p.registro_id]: encontrados }));
  }

  async function resolver(p: Pendiente, aprobar: boolean) {
    setEnviando(true);
    const result = await resolverPendiente({
      tipo: p.tipo,
      registro_id: p.registro_id,
      aprobar,
      motivo: aprobar ? "" : motivo,
    });
    setEnviando(false);

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
        <p className="t-caption mb-3">
          Un alta que se parece a algo ya cargado, o un vínculo con una persona o empresa de otro
          usuario, queda congelado acá: existe, pero no participa de ninguna obra ni la ve nadie
          más hasta que se resuelva.
        </p>

        {pendientes.length === 0 ? (
          <p className="t-body-m">No hay nada esperando.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {pendientes.map((p) => {
              const parecidos = similares[p.registro_id];
              return (
                <li key={p.registro_id} className="card flex flex-col gap-2 p-3">
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <span className="badge badge-warning">{LABEL_TIPO_PENDIENTE[p.tipo]}</span>
                    <span className="t-body-m min-w-0 flex-1 truncate font-semibold">
                      {p.etiqueta}
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
                          disabled={enviando || !motivo.trim()}
                          onClick={() => resolver(p, false)}
                        >
                          Confirmar rechazo
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
                            disabled={enviando}
                            onClick={() => resolver(p, true)}
                          >
                            Aprobar
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
          <div className="flex gap-1">
            {DIAS_OPCIONES.map((d) => (
              <Link
                key={d}
                href={`/obras/pendientes?dias=${d}`}
                className={`btn btn-sm ${d === dias ? "btn-primary" : "btn-ghost"}`}
              >
                {d} días
              </Link>
            ))}
          </div>
        </div>
        <p className="t-caption mb-3">
          Quién resolvió qué y con qué motivo. Sin esto, un rechazo es una fila que desapareció.
        </p>

        {historial.length === 0 ? (
          <p className="t-body-m">Nada resuelto en este período.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {historial.map((h) => (
              <li key={h.aprobacion_id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <span className="t-caption">{formatFechaHora(h.created_at)}</span>
                <span className={`badge ${h.aprobada ? "badge-success" : "badge-error"}`}>
                  {h.aprobada ? "Aprobada" : "Rechazada"}
                </span>
                <span className="t-body-m min-w-0 flex-1 truncate font-semibold">{h.etiqueta}</span>
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
