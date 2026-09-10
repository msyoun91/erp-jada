"use client";

import { useState } from "react";
import { Eye, UserRoundCog } from "lucide-react";
import { FiltroDias } from "@/components/ui/FiltroDias";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { formatFechaHora } from "@/lib/utils";
import type { AccesoAuditoria, TransferenciaAuditoria } from "../types";

// El log solo sirve si alguien puede ver la forma que tiene. Una fila suelta
// no dice nada; "Fulano abrió 340 fichas en dos días" sí, y eso es un conteo
// por usuario, no una lista cronológica.
function resumenPorUsuario(accesos: AccesoAuditoria[]) {
  const porUsuario = new Map<string, { usuario: string; total: number; personas: Set<string> }>();

  for (const a of accesos) {
    const fila = porUsuario.get(a.usuario_id) ?? {
      usuario: a.usuario,
      total: 0,
      personas: new Set<string>(),
    };
    fila.total += 1;
    fila.personas.add(a.persona_id);
    porUsuario.set(a.usuario_id, fila);
  }

  return [...porUsuario.entries()]
    .map(([id, f]) => ({ id, usuario: f.usuario, total: f.total, distintas: f.personas.size }))
    .sort((a, b) => b.total - a.total);
}

export function AuditoriaView({
  accesos,
  transferencias,
  dias,
}: {
  accesos: AccesoAuditoria[];
  transferencias: TransferenciaAuditoria[];
  dias: number;
}) {
  const [usuarioId, setUsuarioId] = useState("");

  const resumen = resumenPorUsuario(accesos);
  const filtrados = usuarioId ? accesos.filter((a) => a.usuario_id === usuarioId) : accesos;
  const { visibles, ...paginado } = usePaginado(filtrados);

  return (
    <div className="flex flex-col gap-6">
      {/* El período sí es de la página: acota las dos secciones. El filtro por
          usuario está adentro de Accesos, que es lo único que filtra. */}
      <FiltroDias href="/obras/auditoria" dias={dias} etiqueta="Período de la auditoría" />

      <section className="card p-4">
        <h2 className="t-h3 mb-1 flex items-center gap-2">
          <Eye size={18} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          Fichas de contacto abiertas
        </h2>
        <p className="t-body-m mb-3 max-w-prose">
          Cada apertura de una ficha de persona queda registrada. Es el único camino por el que la
          app entrega teléfono, whatsapp o email.
        </p>

        {resumen.length === 0 ? (
          <div className="empty-state">
            <p className="t-h3">Nadie abrió una ficha</p>
            <p className="t-body-m mt-1">No hubo accesos al contacto en este período.</p>
          </div>
        ) : (
          <>
            <ul className="mb-4 flex flex-col gap-1">
              {resumen.map((r) => (
                <li key={r.id} className="t-body-m">
                  <span className="font-semibold">{r.usuario}</span> — {r.total}{" "}
                  {r.total === 1 ? "apertura" : "aperturas"} sobre {r.distintas}{" "}
                  {r.distintas === 1 ? "persona" : "personas"} distintas
                </li>
              ))}
            </ul>

            <select
              className="input mb-3 w-auto"
              value={usuarioId}
              onChange={(e) => setUsuarioId(e.target.value)}
              aria-label="Filtrar accesos por usuario"
            >
              <option value="">Todos los usuarios</option>
              {resumen.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.usuario}
                </option>
              ))}
            </select>

            <Paginacion {...paginado} etiqueta="accesos" />
            {/* Una sola línea corrida a la izquierda: con el nombre en `flex-1`
                el sujeto quedaba a 900px de su predicado y el log había que
                barrerlo de punta a punta por renglón. */}
            <ul className="flex flex-col">
              {visibles.map((a) => (
                <li
                  key={a.acceso_id}
                  className="t-body-m row flex flex-wrap items-baseline gap-x-2 border-b border-border px-0 last:border-b-0"
                >
                  <span className="t-caption shrink-0">{formatFechaHora(a.created_at)}</span>
                  <span>
                    <span className="font-semibold">{a.usuario}</span> abrió la ficha de {a.persona}
                    {a.contexto && <span className="t-caption"> · desde «{a.contexto}»</span>}
                  </span>
                </li>
              ))}
            </ul>
          </>
        )}
      </section>

      <section className="card p-4">
        <h2 className="t-h3 mb-1 flex items-center gap-2">
          <UserRoundCog size={18} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          Obras transferidas
        </h2>
        <p className="t-body-m mb-3 max-w-prose">
          Quién le pasó qué obra a quién. Como la obra la ve su responsable, esto es lo que responde
          por qué una obra dejó de aparecer en una cartera.
        </p>

        {transferencias.length === 0 ? (
          <div className="empty-state">
            <p className="t-h3">Sin transferencias</p>
            <p className="t-body-m mt-1">Ninguna obra cambió de responsable en este período.</p>
          </div>
        ) : (
          <ul className="flex flex-col">
            {transferencias.map((t) => (
              <li
                key={t.transferencia_id}
                className="t-body-m row flex flex-wrap items-baseline gap-x-2 border-b border-border px-0 last:border-b-0"
              >
                <span className="t-caption shrink-0">{formatFechaHora(t.created_at)}</span>
                <span>
                  <span className="font-semibold">{t.obra}</span> de {t.de_usuario} a {t.a_usuario}
                  {t.ejecutada_por !== t.de_usuario && ` — la movió ${t.ejecutada_por}`}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
