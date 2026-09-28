"use client";

import { useState } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { labelRol } from "@/lib/entes";
import { formatFecha, formatFechaHora } from "@/lib/utils";
import { historialContacto } from "../actions";
import type { VinculoConRegistro } from "../queries";
import type { Edicion, EdicionContacto } from "../types";

const CAMPO: Record<string, string> = {
  nombre: "Nombre",
  telefono: "Teléfono",
  email: "Email",
  web: "Web",
  notas: "Notas",
};

export function nombreDe(nombres: Record<string, string>, id: string | null, yo: string) {
  if (!id) return "—";
  return id === yo ? "Vos" : (nombres[id] ?? "—");
}

// Dónde figura: el registro con su link si quien lee lo ve; si no, sin nombre.
export function VinculosDeContacto({ vinculos }: { vinculos: VinculoConRegistro[] }) {
  return (
    <div>
      <p className="t-label mb-2">Dónde figura</p>
      {vinculos.length === 0 ? (
        <div className="empty-state">
          <p className="t-body-m">No está vinculado a ninguna obra.</p>
        </div>
      ) : (
        <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {vinculos.map((v) => (
            <li key={v.id} className="row border-b border-border last:border-b-0">
              {v.href ? (
                <Link href={v.href} className="t-body-m block truncate font-medium text-text-primary hover:underline">
                  {v.etiqueta}
                </Link>
              ) : (
                <p className="t-body-m text-text-tertiary">Un registro que no ves</p>
              )}
              <p className="t-caption flex flex-wrap gap-x-3">
                <span>{v.roles.map((r) => labelRol(v.ente, r)).join(" · ")}</span>
                <span>{v.hasta ? `${formatFecha(v.desde)} – ${formatFecha(v.hasta)}` : `Desde ${formatFecha(v.desde)}`}</span>
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

type Entrada = Pick<Edicion, "campo" | "anterior" | "nuevo" | "actor_id" | "created_at">;

function Entradas({ entradas, nombre }: { entradas: Entrada[]; nombre: (id: string | null) => string }) {
  return (
    <ul className="flex flex-col gap-2">
      {entradas.map((e, i) => (
        <li key={i} className="t-caption rounded-md p-2">
          <div className="flex items-center gap-2">
            <span className="font-semibold text-text-secondary">{CAMPO[e.campo] ?? e.campo}</span>
            <span>
              {nombre(e.actor_id)} · {formatFechaHora(e.created_at)}
            </span>
          </div>
          <p className="line-through">{e.anterior || "—"}</p>
          <p className="text-text-secondary">{e.nuevo || "—"}</p>
        </li>
      ))}
    </ul>
  );
}

// Los cambios de teléfono y email de una persona no llegan con la ficha: se
// piden con un botón, que deja registro como "Ver contacto".
export function HistorialEdiciones({
  ediciones,
  nombre,
  personaId,
}: {
  ediciones: Edicion[];
  nombre: (id: string | null) => string;
  personaId?: string;
}) {
  const [contacto, setContacto] = useState<EdicionContacto[] | null>(null);
  const [pidiendo, setPidiendo] = useState(false);
  if (ediciones.length === 0 && !personaId) return null;

  async function pedir(id: string) {
    setPidiendo(true);
    const r = await historialContacto(id);
    setPidiendo(false);
    if (!r.success) toast.error(r.error);
    else setContacto(r.historial);
  }

  return (
    <details>
      <summary className="t-label cursor-pointer py-2">Historial de cambios ({ediciones.length})</summary>
      <Entradas entradas={ediciones} nombre={nombre} />
      {personaId &&
        (contacto === null ? (
          <button className="btn btn-ghost btn-sm mt-2" onClick={() => pedir(personaId)} disabled={pidiendo}>
            {pidiendo ? "Buscando…" : "Ver cambios de teléfono y email"}
          </button>
        ) : contacto.length === 0 ? (
          <p className="t-caption mt-2">Teléfono y email no cambiaron.</p>
        ) : (
          <Entradas entradas={contacto} nombre={nombre} />
        ))}
    </details>
  );
}
