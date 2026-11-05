"use client";

import { useState } from "react";
import { Boxes, ChevronRight, Palette, Plus, SearchX, Tags, Wrench } from "lucide-react";
import { Filtros } from "@/components/ui/Filtros";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { Vacio } from "@/components/ui/Vacio";
import type { Moneda } from "@/lib/monedas";
import {
  activarCategoria,
  activarColor,
  crearCategoria,
  crearColor,
  renombrarCategoria,
  renombrarColor,
} from "../actions";
import { POR_UNIDAD, UNIDAD, hace, textoCosto, textoNumero } from "../etiquetas";
import type { Categoria, Color, Insumo, TipoInsumo } from "../types";
import { CostosPanel, type FilaCosto } from "./CostosPanel";
import { FijoFormPanel } from "./FijoFormPanel";
import { InsumoFicha } from "./InsumoFicha";
import { InsumoFormPanel } from "./InsumoFormPanel";
import { ListaNombresPanel } from "./ListaNombresPanel";
import { ListaPorCategoria, usePaginadoPorCategoria } from "./PorCategoria";

const ESTADOS = [
  { valor: "activos", label: "Activos" },
  { valor: "baja", label: "De baja" },
  { valor: "todos", label: "Todos" },
] as const;
type Estado = (typeof ESTADOS)[number]["valor"];

const TEXTO = {
  insumo: { uno: "insumo", plural: "insumos", nuevo: "Nuevo insumo", buscar: "Buscar insumo…" },
  servicio: { uno: "servicio", plural: "servicios fijos", nuevo: "Nuevo servicio", buscar: "Buscar servicio…" },
} as const;

// Insumos y servicios fijos son la misma tabla y las mismas reglas: una vista, con el tipo.
export function InsumosView({
  tipo,
  insumos,
  categorias,
  colores,
  puedeEditar,
  puedeCostos,
  monedaPrincipal,
}: {
  tipo: TipoInsumo;
  insumos: Insumo[];
  categorias: Categoria[];
  colores: Color[];
  // insumo: `catalogo_cargar` (también colores y categorías) · servicio: `catalogo_fijos_editar`.
  puedeEditar: boolean;
  // insumo: `catalogo_costos` · servicio: `catalogo_fijos_editar`.
  puedeCostos: boolean;
  monedaPrincipal: Moneda;
}) {
  const [texto, setTexto] = useState("");
  const [categoriaId, setCategoriaId] = useState("");
  const [estado, setEstado] = useState<Estado>("activos");
  const [porCosto, setPorCosto] = useState(false);
  const [agrupar, setAgrupar] = useState(true);
  const [abierto, setAbierto] = useState<string | null>(null);
  const [editando, setEditando] = useState<Insumo | "nuevo" | null>(null);
  const [costos, setCostos] = useState<{ titulo: string; filas: FilaCosto[] } | null>(null);
  const [panel, setPanel] = useState<"categorias" | "colores" | null>(null);
  const t = TEXTO[tipo];
  const nombreCategoria = new Map(categorias.map((c) => [c.id, c.nombre]));
  const nombreColor = new Map(colores.map((c) => [c.id, c.nombre]));

  const q = texto.trim().toLowerCase();
  const filtrados = insumos.filter(
    (i) =>
      (estado === "todos" || (estado === "activos") === i.activo) &&
      (!categoriaId || i.categoria_id === categoriaId) &&
      i.nombre.toLowerCase().includes(q),
  );
  // El costo más viejo primero: sin costo, antes que todos.
  const ordenados = porCosto ? [...filtrados].sort((a, b) => masViejo(a).localeCompare(masViejo(b))) : filtrados;
  const { grupos, paginado } = usePaginadoPorCategoria(ordenados, (i) => i.categoria_id, nombreCategoria, agrupar);
  const ficha = insumos.find((i) => i.id === abierto) ?? null;

  function filasCosto(lista: Insumo[]): FilaCosto[] {
    return lista.flatMap((i) =>
      i.variantes
        .filter((v) => v.activo)
        .map((v) => ({
          variante_id: v.id,
          nombre: v.color_id ? `${i.nombre} · ${nombreColor.get(v.color_id)}` : i.nombre,
          unidad: i.unidad,
          costo: v.costo,
        })),
    );
  }

  const cargables = filasCosto(filtrados.filter((i) => i.activo));

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        {puedeEditar && (
          <button className="btn btn-primary" onClick={() => setEditando("nuevo")}>
            <Plus size={16} />
            {t.nuevo}
          </button>
        )}
        {puedeCostos && cargables.length > 0 && (
          <button
            className="btn btn-secondary"
            onClick={() => setCostos({ titulo: `Cargar costos (${cargables.length})`, filas: cargables })}
          >
            Cargar costos
          </button>
        )}
        {/* En un menú: en mobile, con los filtros, eran cinco renglones antes del primer insumo. */}
        <OverflowMenu
          enBarra
          items={[
            {
              label: "Categorías",
              icon: <Tags size={14} />,
              onClick: () => setPanel("categorias"),
            },
            ...(tipo === "insumo"
              ? [
                  {
                    label: "Colores",
                    icon: <Palette size={14} />,
                    onClick: () => setPanel("colores"),
                  },
                ]
              : []),
          ]}
        />
      </div>

      <div className="mb-4">
        <Filtros
          buscador={<SearchInput value={texto} onChange={setTexto} placeholder={t.buscar} />}
          activos={[categoriaId !== "", estado !== "activos", porCosto, !agrupar].filter(Boolean).length}
        >
          <select
            className="input w-auto"
            value={categoriaId}
            onChange={(e) => setCategoriaId(e.target.value)}
            aria-label="Filtrar por categoría"
          >
            <option value="">Todas las categorías</option>
            {categorias.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
                {c.activo ? "" : " (de baja)"}
              </option>
            ))}
          </select>
          <select
            className="input w-auto"
            value={estado}
            onChange={(e) => setEstado(e.target.value as Estado)}
            aria-label="Filtrar por estado"
          >
            {ESTADOS.map((e) => (
              <option key={e.valor} value={e.valor}>
                {e.label}
              </option>
            ))}
          </select>
          {puedeCostos && (
            <select
              className="input w-auto"
              value={porCosto ? "costo" : "nombre"}
              onChange={(e) => setPorCosto(e.target.value === "costo")}
              aria-label="Ordenar"
            >
              <option value="nombre">Por nombre</option>
              <option value="costo">Costo más viejo primero</option>
            </select>
          )}
          <label className="tap-target flex items-center gap-2">
            <input type="checkbox" checked={agrupar} onChange={(e) => setAgrupar(e.target.checked)} />
            <span className="t-body-m">Agrupar por categoría</span>
          </label>
        </Filtros>
      </div>

      <Paginacion {...paginado} etiqueta={t.plural} />

      {filtrados.length === 0 ? (
        <Vacio
          icono={insumos.length > 0 ? SearchX : tipo === "insumo" ? Boxes : Wrench}
          titulo={insumos.length === 0 ? `Sin ${t.plural} todavía` : "Sin resultados"}
        >
          {insumos.length === 0
            ? puedeEditar
              ? `Cargá el primero con "${t.nuevo}". Antes, armá sus categorías en el menú ⋯.`
              : `Todavía nadie cargó ${t.plural}.`
            : "Probá con otro término o cambiá los filtros."}
        </Vacio>
      ) : (
        <ListaPorCategoria
          grupos={grupos}
          fila={(i) => (
            <li key={i.id} className="border-b border-border last:border-b-0">
              <button
                className="row tap-target flex w-full items-center gap-3 text-left hover:bg-bg-subtle"
                onClick={() => setAbierto(i.id)}
              >
                <div className="min-w-0 flex-1">
                  <p
                    className={`t-body-m truncate font-medium ${i.activo ? "text-text-primary" : "text-text-tertiary"}`}
                  >
                    {i.nombre}
                  </p>
                  <p className="t-caption truncate">
                    {[
                      !agrupar && nombreCategoria.get(i.categoria_id),
                      UNIDAD[i.unidad],
                      tipo === "insumo" && i.peso !== null && `${textoNumero(i.peso)} kg/${POR_UNIDAD[i.unidad]}`,
                      tipo === "insumo" && i.espesor !== null && `${textoNumero(i.espesor)} mm`,
                      tipo === "insumo" && textoColores(i, nombreColor),
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                </div>
                {!i.activo && <span className="badge badge-neutral shrink-0">De baja</span>}
                {puedeCostos && i.activo && <ResumenCosto insumo={i} />}
                <ChevronRight size={16} className="shrink-0 text-text-tertiary" />
              </button>
            </li>
          )}
        />
      )}

      {ficha && (
        <InsumoFicha
          tipo={tipo}
          insumo={ficha}
          categorias={categorias}
          colores={colores}
          puedeEditar={puedeEditar}
          puedeCostos={puedeCostos}
          onEditar={() => setEditando(ficha)}
          onCostos={() => setCostos({ titulo: `Costo de ${ficha.nombre}`, filas: filasCosto([ficha]) })}
          onClose={() => setAbierto(null)}
        />
      )}

      {editando &&
        (tipo === "insumo" ? (
          <InsumoFormPanel
            insumo={editando === "nuevo" ? null : editando}
            categorias={categorias}
            colores={colores}
            onClose={() => setEditando(null)}
          />
        ) : (
          <FijoFormPanel
            fijo={editando === "nuevo" ? null : editando}
            categorias={categorias}
            monedaPrincipal={monedaPrincipal}
            onClose={() => setEditando(null)}
          />
        ))}

      {costos && (
        <CostosPanel
          titulo={costos.titulo}
          filas={costos.filas}
          monedaPrincipal={monedaPrincipal}
          onClose={() => setCostos(null)}
        />
      )}

      {panel === "categorias" && (
        <ListaNombresPanel
          titulo={tipo === "insumo" ? "Categorías de insumo" : "Categorías de servicio"}
          regla="El nombre se edita hasta que tiene algo adentro; se da de baja sin nada activo adentro."
          nueva="Nueva categoría"
          items={categorias}
          puedeEditar={puedeEditar}
          onCrear={(nombre) => crearCategoria({ tipo, nombre })}
          onRenombrar={(id, nombre) => renombrarCategoria({ id, nombre })}
          onActivar={(id, activo) => activarCategoria({ id, activo })}
          onClose={() => setPanel(null)}
        />
      )}

      {panel === "colores" && (
        <ListaNombresPanel
          titulo="Colores"
          regla="Una lista para todos los insumos. El nombre se edita hasta que un insumo lo usa; se da de baja sin variantes activas."
          nueva="Nuevo color"
          items={colores}
          puedeEditar={puedeEditar}
          onCrear={(nombre) => crearColor({ nombre })}
          onRenombrar={(id, nombre) => renombrarColor({ id, nombre })}
          onActivar={(id, activo) => activarColor({ id, activo })}
          onClose={() => setPanel(null)}
        />
      )}
    </div>
  );
}

function masViejo(i: Insumo): string {
  return i.variantes
    .filter((v) => v.activo)
    .map((v) => v.costo?.desde ?? "")
    .reduce((a, b) => (b < a ? b : a), "￿");
}

function textoColores(i: Insumo, nombre: Map<string, string>): string {
  if (!i.con_color) return "color indistinto";
  const activas = i.variantes.filter((v) => v.activo && v.color_id);
  return activas.length === 0 ? "sin colores" : activas.map((v) => nombre.get(v.color_id ?? "")).join(", ");
}

function ResumenCosto({ insumo }: { insumo: Insumo }) {
  const activas = insumo.variantes.filter((v) => v.activo);
  const sinCosto = activas.filter((v) => !v.costo).length;
  if (activas.length === 0) return null;
  if (sinCosto > 0) {
    return (
      <span className="badge badge-warning shrink-0">
        {activas.length === 1 ? "Sin costo" : `${sinCosto} sin costo`}
      </span>
    );
  }
  const viejo = masViejo(insumo);
  return (
    <span className="t-caption shrink-0 text-right">
      {activas.length === 1 && activas[0].costo
        ? textoCosto(activas[0].costo, insumo.unidad)
        : `${activas.length} colores`}
      <br />
      {hace(viejo)}
    </span>
  );
}
