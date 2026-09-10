"use client";

import { useState } from "react";
import Link from "next/link";
import { Building2, Plus } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import {
  BADGE_ESTADO,
  ESTADOS_OBRA,
  LABEL_ESTADO,
  LABEL_TIPO,
  TIPOS_OBRA,
  type EstadoObra,
  type ObraListado,
  type TipoObra,
} from "../types";
import { AlcanceToggle } from "./AlcanceToggle";
import { ObraFormPanel } from "./ObraFormPanel";

// Abajo de `md` la fila son dos líneas: nombre arriba, metadata abajo. Arriba,
// grilla de anchos fijos — con la metadata como items `flex-wrap` el único que
// cedía ancho era el nombre, que es el dato que identifica la fila, y en
// escritorio los chips quedaban a distinta altura horizontal en cada fila.
const COLUMNAS = "md:grid-cols-[minmax(0,1fr)_7.5rem_9rem_9rem_11rem]";
const COLUMNAS_CON_RESPONSABLE =
  "md:grid-cols-[minmax(0,1fr)_7.5rem_9rem_9rem_11rem_8rem]";

export function ObrasView({
  obras,
  puedeCrear,
  puedeTransferir,
  miId,
}: {
  obras: ObraListado[];
  puedeCrear: boolean;
  puedeTransferir: boolean;
  miId: string | null;
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
          className="input w-auto"
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
          className="input w-auto"
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

      {puedeTransferir && (
        <div className="mb-3 flex items-center gap-2">
          <AlcanceToggle />
          <span className="t-caption">Podés transferir obras, así que las ves todas.</span>
        </div>
      )}

      <Paginacion {...paginado} etiqueta="obras" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <Building2 size={30} strokeWidth={1.5} className="mx-auto mb-3" />
          <p className="t-h3">{obras.length === 0 ? "Sin obras todavía" : "Sin resultados"}</p>
          <p className="t-body-m mt-1">
            {obras.length === 0
              ? puedeCrear
                ? "Alcanza con el nombre y el tipo — el resto se completa después."
                : 'Creá la primera con "Nueva obra".'
              : "Probá con otro término o con otro filtro."}
          </p>
        </div>
      ) : (
        <ul className="flex flex-col gap-2">
          {visibles.map((o) => (
            <li key={o.id}>
              <Link
                href={`/obras/${o.id}`}
                className={`card card-link tap-target flex flex-col gap-y-1 p-3 hover:bg-bg-subtle md:grid md:items-center md:gap-x-3 ${
                  puedeTransferir ? COLUMNAS_CON_RESPONSABLE : COLUMNAS
                }`}
              >
                <span className="flex min-w-0 items-center gap-2">
                  <span className="t-body-m truncate font-semibold text-text-primary">
                    {o.nombre}
                  </span>
                  {/* Congelada: existe y la ve su responsable, pero todavía no
                      se le puede vincular nada. */}
                  {o.pendiente && <span className="badge badge-warning shrink-0">Pendiente</span>}
                  {miId && o.responsable_id !== miId && (
                    <span className="badge badge-neutral shrink-0">Ajena</span>
                  )}
                </span>
                {/* `md:contents` disuelve este envoltorio en la grilla: una sola
                    escritura del marcado sirve para la línea que envuelve en
                    mobile y para las celdas de escritorio. Las celdas vacías se
                    ocultan abajo de `md` para no dejar un hueco de `gap`. */}
                <span className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1 md:contents">
                  <span className={`badge shrink-0 md:justify-self-start ${BADGE_ESTADO[o.estado]}`}>
                    {LABEL_ESTADO[o.estado]}
                  </span>
                  <span className="truncate">{LABEL_TIPO[o.tipo]}</span>
                  <span className={o.localidad ? "truncate" : "hidden md:block"}>
                    {o.localidad}
                  </span>
                  <span className="truncate">
                    {o.empresas} {o.empresas === 1 ? "empresa" : "empresas"} · {o.personas}{" "}
                    {o.personas === 1 ? "persona" : "personas"}
                  </span>
                  {puedeTransferir && (
                    <span className={o.responsable ? "truncate" : "hidden md:block"}>
                      {o.responsable?.nombre}
                    </span>
                  )}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}

      {creando && <ObraFormPanel onClose={() => setCreando(false)} />}
    </div>
  );
}
