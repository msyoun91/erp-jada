"use client";

import { useState } from "react";
import Link from "next/link";
import { Eye, UserRoundCog } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { formatFechaHora } from "@/lib/utils";
import type { AccesoAuditoria, TransferenciaAuditoria } from "../types";

const DIAS_OPCIONES = [7, 30, 90];

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
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex gap-1">
          {DIAS_OPCIONES.map((d) => (
            <Link
              key={d}
              href={`/obras/auditoria?dias=${d}`}
              className={`btn btn-sm ${d === dias ? "btn-primary" : "btn-ghost"}`}
            >
              {d} días
            </Link>
          ))}
        </div>
        <select
          className="input w-auto py-1.5"
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
      </div>

      <section className="card p-4">
        <h2 className="t-h3 mb-1 flex items-center gap-2">
          <Eye size={18} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          Fichas de contacto abiertas
        </h2>
        <p className="t-caption mb-3">
          Cada apertura de una ficha de persona queda registrada. Es el único camino por el que la
          app entrega teléfono, whatsapp o email.
        </p>

        {resumen.length === 0 ? (
          <p className="t-body-m">Nadie abrió una ficha en este período.</p>
        ) : (
          <ul className="mb-4 flex flex-col gap-1">
            {resumen.map((r) => (
              <li key={r.id} className="t-body-m">
                <span className="font-semibold">{r.usuario}</span> — {r.total}{" "}
                {r.total === 1 ? "apertura" : "aperturas"} sobre {r.distintas}{" "}
                {r.distintas === 1 ? "persona" : "personas"} distintas
              </li>
            ))}
          </ul>
        )}

        {filtrados.length > 0 && (
          <>
            <Paginacion {...paginado} etiqueta="accesos" />
            <ul className="flex flex-col gap-2">
              {visibles.map((a) => (
                <li
                  key={a.acceso_id}
                  className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3"
                >
                  <span className="t-caption">{formatFechaHora(a.created_at)}</span>
                  <span className="t-body-m min-w-0 flex-1 truncate font-semibold">
                    {a.usuario}
                  </span>
                  <span className="t-body-m">abrió la ficha de {a.persona}</span>
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
        <p className="t-caption mb-3">
          Quién le pasó qué obra a quién. Como la obra la ve su responsable, esto es lo que responde
          por qué una obra dejó de aparecer en una cartera.
        </p>

        {transferencias.length === 0 ? (
          <p className="t-body-m">No hubo transferencias en este período.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {transferencias.map((t) => (
              <li key={t.transferencia_id} className="card flex flex-wrap items-center gap-x-3 gap-y-1 p-3">
                <span className="t-caption">{formatFechaHora(t.created_at)}</span>
                <span className="t-body-m min-w-0 flex-1 truncate font-semibold">{t.obra}</span>
                <span className="t-body-m">
                  de {t.de_usuario} a {t.a_usuario}
                </span>
                {t.ejecutada_por !== t.de_usuario && (
                  <span className="t-caption">la movió {t.ejecutada_por}</span>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
