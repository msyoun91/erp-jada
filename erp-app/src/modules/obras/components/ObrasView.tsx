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

// "Perdida" no ensucia la vista por defecto: solo aparece al abrir su chip.
const ORDENES = {
  reciente: {
    label: "Más recientes",
    fn: (a: ObraListado, b: ObraListado) => b.updated_at.localeCompare(a.updated_at),
  },
  alta: {
    label: "Fecha de alta",
    fn: (a: ObraListado, b: ObraListado) => b.created_at.localeCompare(a.created_at),
  },
  estado: {
    label: "Estado",
    fn: (a: ObraListado, b: ObraListado) =>
      ESTADOS_OBRA.indexOf(a.estado) - ESTADOS_OBRA.indexOf(b.estado),
  },
} as const;

// Misma forma que el toggle de RolesPicker: el borde es la señal que sobrevive
// al contraste bajo, el relleno acompaña.
const chipEstado = (activo: boolean) =>
  `tap-target t-caption flex items-center gap-1.5 rounded-md border px-3 py-1 ${
    activo
      ? "border-brand-500 bg-brand-50 font-semibold text-brand-700"
      : "border-border text-text-tertiary"
  }`;

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
  const [orden, setOrden] = useState<keyof typeof ORDENES>("reciente");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  // Los chips de estado cuentan sobre lo que dejan pasar los otros filtros, no
  // sobre sí mismos: así el número es lo que se ve al tocarlos.
  const base = obras.filter((o) => {
    if (q && !o.nombre.toLowerCase().includes(q) && !(o.localidad ?? "").toLowerCase().includes(q))
      return false;
    if (tipo && o.tipo !== tipo) return false;
    return true;
  });
  const conteo = base.reduce<Partial<Record<EstadoObra, number>>>((acc, o) => {
    acc[o.estado] = (acc[o.estado] ?? 0) + 1;
    return acc;
  }, {});
  // Sin chip elegido, "Perdida" queda fuera: solo se ve al abrir su chip.
  const filtradas = estado
    ? base.filter((o) => o.estado === estado)
    : base.filter((o) => o.estado !== "perdida");
  const visiblesEnTodas = base.length - (conteo.perdida ?? 0);
  const ordenadas = [...filtradas].sort(ORDENES[orden].fn);
  const { visibles, ...paginado } = usePaginado(ordenadas);

  return (
    <div>
      <div className="mb-4 flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-3">
          <SearchInput value={texto} onChange={setTexto} placeholder="Buscar obra o localidad…" />
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
          <select
            className="input w-auto"
            value={orden}
            onChange={(e) => setOrden(e.target.value as keyof typeof ORDENES)}
            aria-label="Ordenar"
          >
            {Object.entries(ORDENES).map(([k, { label }]) => (
              <option key={k} value={k}>
                {label}
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

        <div className="flex flex-wrap gap-2" role="group" aria-label="Filtrar por estado">
          <button
            type="button"
            className={chipEstado(estado === "")}
            aria-pressed={estado === ""}
            onClick={() => setEstado("")}
          >
            Todas <span className="tabular-nums opacity-70">{visiblesEnTodas}</span>
          </button>
          {ESTADOS_OBRA.map((e) => (
            <button
              key={e}
              type="button"
              className={chipEstado(estado === e)}
              aria-pressed={estado === e}
              onClick={() => setEstado(e)}
            >
              {LABEL_ESTADO[e]} <span className="tabular-nums opacity-70">{conteo[e] ?? 0}</span>
            </button>
          ))}
        </div>
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
