"use client";

import { useState } from "react";
import Link from "next/link";
import { Building2, HardHat, UserRound, X } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { formatFecha } from "@/lib/utils";
import { revocarEmpresa, revocarObra, revocarPersona } from "../actions";
import type { CompartidoRow } from "../types";

const ICONO = {
  obra: HardHat,
  empresa: Building2,
  persona: UserRound,
} as const;

const HREF = {
  obra: (id: string) => `/obras/${id}`,
  empresa: (id: string) => `/obras/empresas/${id}`,
  persona: (id: string) => `/obras/personas/${id}`,
} as const;

function revocar(fila: CompartidoRow) {
  if (fila.tipo === "obra") return revocarObra(fila.entidad_id, fila.usuario_id);
  if (fila.tipo === "empresa") return revocarEmpresa(fila.entidad_id, fila.usuario_id);
  return revocarPersona(fila.entidad_id, fila.usuario_id);
}

const filaKey = (f: CompartidoRow) => `${f.tipo}:${f.entidad_id}:${f.usuario_id}`;
const padreKey = (f: CompartidoRow) =>
  f.origen_tipo && f.origen_id ? `${f.origen_tipo}:${f.origen_id}:${f.usuario_id}` : null;

export function CompartidoView({ filas }: { filas: CompartidoRow[] }) {
  const [confirmando, setConfirmando] = useState<CompartidoRow | null>(null);

  async function correr(fila: CompartidoRow) {
    const result = await revocar(fila);
    if (result.success) toast.success("Acceso revocado");
    else toast.error(result.error);
  }

  if (filas.length === 0) {
    return (
      <div className="empty-state">
        <p className="t-h3">No compartiste nada</p>
        <p className="t-body-m mt-1">
          Compartí una obra, empresa o persona desde su ficha y va a aparecer acá.
        </p>
      </div>
    );
  }

  // Lo compartido en cascada se anida bajo la obra/empresa de la que cuelga.
  // El padre siempre está en el mismo resultado (obras_compartir_* inserta su
  // grant antes que la cascada); si no estuviera, la fila queda como raíz.
  const presentes = new Set(filas.map(filaKey));
  const hijosDe = new Map<string, CompartidoRow[]>();
  for (const f of filas) {
    const pk = padreKey(f);
    if (pk && presentes.has(pk)) {
      const lista = hijosDe.get(pk);
      if (lista) lista.push(f);
      else hijosDe.set(pk, [f]);
    }
  }
  const raices = filas.filter((f) => {
    const pk = padreKey(f);
    return !pk || !presentes.has(pk);
  });

  function Fila({ f, anidada }: { f: CompartidoRow; anidada: boolean }) {
    const Icono = ICONO[f.tipo];
    const hijos = hijosDe.get(filaKey(f)) ?? [];
    return (
      <li>
        <div className="card flex items-center gap-3 p-3">
          <Icono size={18} strokeWidth={1.75} className="text-brand-500 shrink-0" />
          <div className="min-w-0 flex-1">
            <Link
              href={HREF[f.tipo](f.entidad_id)}
              className="t-body-m block truncate font-semibold hover:underline"
            >
              {f.entidad_nombre}
            </Link>
            <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1">
              <span className="t-caption">con {f.usuario_nombre}</span>
              <span className="t-caption">· {formatFecha(f.compartida_el)}</span>
              {anidada && f.origen_tipo && (
                <span className="badge badge-neutral">
                  vía {f.origen_tipo === "obra" ? "la obra" : "la empresa"}
                </span>
              )}
            </div>
          </div>
          <button
            type="button"
            className="btn-ghost text-tertiary tap-target shrink-0"
            aria-label={`Revocar acceso de ${f.usuario_nombre} a ${f.entidad_nombre}`}
            onClick={() => setConfirmando(f)}
          >
            <X size={16} strokeWidth={1.75} />
          </button>
        </div>
        {hijos.length > 0 && (
          <ul className="border-border mt-2 ml-4 flex flex-col gap-2 border-l pl-4">
            {hijos.map((h) => (
              <Fila key={filaKey(h)} f={h} anidada />
            ))}
          </ul>
        )}
      </li>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      <p className="t-body-m mb-2 max-w-prose">
        Todo lo que compartiste, con quién y de qué origen. Lo que compartiste dentro de una obra o
        empresa aparece anidado debajo de ella. Quien recibe lo ve completo pero no puede editarlo
        ni re-compartirlo. Revocar una obra o empresa también saca lo que se compartió junto con
        ella.
      </p>

      <ul className="flex flex-col gap-2">
        {raices.map((f) => (
          <Fila key={filaKey(f)} f={f} anidada={false} />
        ))}
      </ul>

      {confirmando && (
        <ConfirmModal
          title="Revocar acceso"
          mensaje={`${confirmando.usuario_nombre} deja de ver «${confirmando.entidad_nombre}».${
            confirmando.tipo === "persona"
              ? ""
              : " Lo que se compartió junto con esta " + confirmando.tipo + " también se revoca."
          }`}
          confirmLabel="Revocar"
          onConfirm={() => correr(confirmando)}
          onClose={() => setConfirmando(null)}
        />
      )}
    </div>
  );
}
