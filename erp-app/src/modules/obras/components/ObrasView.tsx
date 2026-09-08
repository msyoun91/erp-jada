"use client";

import { useState } from "react";
import Link from "next/link";
import { Building2, Plus } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import {
  ESTADOS_OBRA,
  LABEL_ESTADO,
  LABEL_TIPO,
  TIPOS_OBRA,
  type EstadoObra,
  type ObraListado,
  type TipoObra,
} from "../types";
import { ObraFormPanel } from "./ObraFormPanel";

const BADGE_ESTADO: Record<EstadoObra, string> = {
  idea: "badge-neutral",
  en_construccion: "badge-info",
  perdida: "badge-error",
  terminada: "badge-success",
};

export function ObrasView({
  obras,
  puedeCrear,
  puedeTransferir,
}: {
  obras: ObraListado[];
  puedeCrear: boolean;
  puedeTransferir: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [estado, setEstado] = useState<EstadoObra | "">("");
  const [tipo, setTipo] = useState<TipoObra | "">("");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  const filtradas = obras.filter((o) => {
    if (q && !o.nombre.toLowerCase().includes(q) && !(o.localidad ?? "").toLowerCase().includes(q))
      return false;
    if (estado && o.estado !== estado) return false;
    if (tipo && o.tipo !== tipo) return false;
    return true;
  });
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar obra o localidad…" />
        <select
          className="input w-auto py-1.5"
          value={estado}
          onChange={(e) => setEstado(e.target.value as EstadoObra | "")}
          aria-label="Filtrar por estado"
        >
          <option value="">Todos los estados</option>
          {ESTADOS_OBRA.map((e) => (
            <option key={e} value={e}>
              {LABEL_ESTADO[e]}
            </option>
          ))}
        </select>
        <select
          className="input w-auto py-1.5"
          value={tipo}
          onChange={(e) => setTipo(e.target.value as TipoObra | "")}
          aria-label="Filtrar por tipo"
        >
          <option value="">Todos los tipos</option>
          {TIPOS_OBRA.map((t) => (
            <option key={t} value={t}>
              {LABEL_TIPO[t]}
            </option>
          ))}
        </select>
        {puedeCrear && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nueva obra
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="obras" />

      {puedeTransferir && (
        <p className="t-caption mb-2">Ves todas las obras porque podés transferirlas.</p>
      )}

      {filtradas.length === 0 ? (
        <div className="card flex flex-col items-center gap-2 p-8 text-center">
          <Building2 size={32} strokeWidth={1.5} className="text-text-tertiary" />
          <p className="t-body-m">
            {obras.length === 0
              ? "Todavía no hay obras cargadas."
              : "Ninguna obra coincide con el filtro."}
          </p>
          {obras.length === 0 && puedeCrear && (
            <p className="t-caption">
              Alcanza con el nombre y el tipo — el resto se completa después.
            </p>
          )}
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {visibles.map((o) => (
            <li key={o.id}>
              <Link
                href={`/obras/${o.id}`}
                className="card flex min-h-[44px] flex-wrap items-center gap-x-3 gap-y-1 p-3 hover:bg-bg-subtle"
              >
                <span className="t-body-m min-w-0 flex-1 truncate font-semibold">{o.nombre}</span>
                {/* Congelada: existe y la ve su responsable, pero todavía no
                    se le puede vincular nada. */}
                {o.pendiente && <span className="badge badge-warning">Pendiente</span>}
                <span className={`badge ${BADGE_ESTADO[o.estado]}`}>{LABEL_ESTADO[o.estado]}</span>
                <span className="t-caption">{LABEL_TIPO[o.tipo]}</span>
                {o.localidad && <span className="t-caption">{o.localidad}</span>}
                <span className="t-caption">
                  {o.empresas} {o.empresas === 1 ? "empresa" : "empresas"} · {o.personas}{" "}
                  {o.personas === 1 ? "persona" : "personas"}
                </span>
                {puedeTransferir && o.responsable && (
                  <span className="t-caption">{o.responsable.nombre}</span>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}

      {creando && <ObraFormPanel onClose={() => setCreando(false)} />}
    </div>
  );
}
