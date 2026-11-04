"use client";

import { useState } from "react";
import Link from "next/link";
import { Plus } from "lucide-react";
import { Paginacion } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { activarCategoria, crearCategoria, renombrarCategoria } from "../actions";
import { ESTADO_VERSION, versionPrincipal } from "../etiquetas";
import type { Categoria, Paquete } from "../types";
import { ListaNombresPanel } from "./ListaNombresPanel";
import { PaqueteAltaModal } from "./PaqueteAltaModal";
import { ListaPorCategoria, usePaginadoPorCategoria } from "./PorCategoria";

const ESTADOS = [
  { valor: "venta", label: "A la venta" },
  { valor: "sin_publicar", label: "Sin publicar" },
  { valor: "baja", label: "De baja" },
  { valor: "todos", label: "Todos" },
] as const;
type Estado = (typeof ESTADOS)[number]["valor"];

function estadoDe(p: Paquete): Exclude<Estado, "todos"> {
  if (!p.activo) return "baja";
  return p.versiones.some((v) => v.estado === "publicado") ? "venta" : "sin_publicar";
}

export function PaquetesView({
  paquetes,
  categorias,
  puedeArmar,
  puedeAprobar,
}: {
  paquetes: Paquete[];
  categorias: Categoria[];
  puedeArmar: boolean;
  puedeAprobar: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [categoriaId, setCategoriaId] = useState("");
  const [estado, setEstado] = useState<Estado>("todos");
  const [agrupar, setAgrupar] = useState(true);
  const [creando, setCreando] = useState(false);
  const [verCategorias, setVerCategorias] = useState(false);
  const nombreCategoria = new Map(categorias.map((c) => [c.id, c.nombre]));

  const q = texto.trim().toLowerCase();
  const filtrados = paquetes
    .map((p) => ({ paquete: p, version: versionPrincipal(p) }))
    .filter(
      ({ paquete, version }) =>
        version &&
        (estado === "todos" || estadoDe(paquete) === estado) &&
        (!categoriaId || version.categoria_id === categoriaId) &&
        paquete.versiones.some((v) => v.nombre.toLowerCase().includes(q)),
    )
    .sort((a, b) => (a.version?.nombre ?? "").localeCompare(b.version?.nombre ?? ""));
  const { grupos, paginado } = usePaginadoPorCategoria(
    filtrados,
    (f) => f.version?.categoria_id ?? "",
    nombreCategoria,
    agrupar,
  );
  const porRevisar = paquetes.flatMap((p) => p.versiones.filter((v) => v.estado === "en_revision"));

  return (
    <div className="flex flex-col gap-4">
      {puedeAprobar && porRevisar.length > 0 && (
        <section className="flex flex-col gap-2">
          <h2 className="t-label">Por revisar ({porRevisar.length})</h2>
          <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
            {porRevisar.map((v) => (
              <li key={v.id} className="border-b border-border last:border-b-0">
                <Link
                  href={`/catalogo/paquetes/versiones/${v.id}`}
                  className="row tap-target flex items-center gap-3 hover:bg-bg-subtle"
                >
                  <span className="t-body-m min-w-0 flex-1 truncate font-medium">
                    {v.nombre} · v{v.numero}
                  </span>
                  <span className="t-caption shrink-0">{nombreCategoria.get(v.categoria_id)}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar paquete…" />
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
        <label className="tap-target flex items-center gap-2">
          <input type="checkbox" checked={agrupar} onChange={(e) => setAgrupar(e.target.checked)} />
          <span className="t-body-m">Agrupar por categoría</span>
        </label>
      </div>

      <div className="flex flex-wrap gap-2">
        {puedeArmar && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nuevo paquete
          </button>
        )}
        <button className="btn btn-secondary" onClick={() => setVerCategorias(true)}>
          Categorías
        </button>
        {puedeAprobar && (
          <Link href="/catalogo/paquetes/referencia" className="btn btn-secondary">
            Precios de referencia
          </Link>
        )}
      </div>

      <div>
        <Paginacion {...paginado} etiqueta="paquetes" />
        {filtrados.length === 0 ? (
          <div className="empty-state">
            <p className="t-h3">{paquetes.length === 0 ? "Sin paquetes todavía" : "Sin resultados"}</p>
            <p className="t-body-m mt-1">
              {paquetes.length === 0
                ? puedeArmar
                  ? 'Armá el primero con "Nuevo paquete". Antes, cargá sus categorías.'
                  : "Todavía nadie armó paquetes."
                : "Probá con otro término o cambiá los filtros."}
            </p>
          </div>
        ) : (
          <ListaPorCategoria
            grupos={grupos}
            fila={({ paquete, version }) => {
              if (!version) return null;
              const abierta = paquete.versiones.find((v) => v.estado === "borrador" || v.estado === "en_revision");
              const e = estadoDe(paquete);
              return (
                <li key={paquete.id} className="border-b border-border last:border-b-0">
                  <Link
                    href={`/catalogo/paquetes/versiones/${(abierta ?? version).id}`}
                    className="row tap-target flex items-center gap-3 hover:bg-bg-subtle"
                  >
                    <div className="min-w-0 flex-1">
                      <p
                        className={`t-body-m truncate font-medium ${e === "baja" ? "text-text-tertiary" : "text-text-primary"}`}
                      >
                        {version.nombre}
                      </p>
                      <p className="t-caption truncate">
                        {[
                          !agrupar && nombreCategoria.get(version.categoria_id),
                          e === "baja" && `De baja por ${paquete.baja_por ?? "decisión de Técnica"}`,
                          abierta && `v${abierta.numero} ${ESTADO_VERSION[abierta.estado].label.toLowerCase()}`,
                        ]
                          .filter(Boolean)
                          .join(" · ")}
                      </p>
                    </div>
                    <span
                      className={`badge shrink-0 ${e === "venta" ? "badge-success" : e === "baja" ? "badge-neutral" : "badge-warning"}`}
                    >
                      {ESTADOS.find((x) => x.valor === e)?.label}
                    </span>
                  </Link>
                </li>
              );
            }}
          />
        )}
      </div>

      {creando && <PaqueteAltaModal categorias={categorias} onClose={() => setCreando(false)} />}

      {verCategorias && (
        <ListaNombresPanel
          titulo="Categorías de paquete"
          regla="El vendedor elige primero la categoría. El nombre queda fijo desde que se envía una versión con ella; se da de baja si ningún paquete a la venta la usa."
          nueva="Nueva categoría"
          items={categorias}
          puedeEditar={puedeArmar}
          onCrear={(nombre) => crearCategoria({ tipo: "paquete", nombre })}
          onRenombrar={(id, nombre) => renombrarCategoria({ id, nombre })}
          onActivar={(id, activo) => activarCategoria({ id, activo })}
          onClose={() => setVerCategorias(false)}
        />
      )}
    </div>
  );
}
