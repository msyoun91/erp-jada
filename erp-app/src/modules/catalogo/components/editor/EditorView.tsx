"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowLeft, Plus, TriangleAlert } from "lucide-react";
import { formulaAparte, textoMedida } from "../../etiquetas";
import type { Categoria, Color, Contenido, InsumoBasico, Material, Variable, Version } from "../../types";
import { DatosVersion } from "./DatosVersion";
import { Fila } from "./Fila";
import { MaterialPanel } from "./MaterialPanel";
import { nombresDisponibles } from "./Nombres";
import { PiezaPanel } from "./PiezaPanel";
import { VariablePanel } from "./VariablePanel";

type Panel =
  | { tipo: "pieza"; id: string | null }
  | { tipo: "variable"; id: string | null; piezaId: string | null }
  | { tipo: "material"; id: string | null; piezaId: string; sumarOpcion?: boolean };

// Un borrador puede quedar a medias: cada cambio se guarda solo, y lo que falta lo dice "Lo que frena el
// envío", que la base recalcula con cada guardado.
export function EditorView({
  version,
  contenido,
  categorias,
  colores,
  insumos,
  frena,
}: {
  version: Version;
  contenido: Contenido;
  categorias: Categoria[];
  colores: Color[];
  insumos: InsumoBasico[];
  frena: string[];
}) {
  const [panel, setPanel] = useState<Panel | null>(null);
  const porId = new Map(insumos.map((i) => [i.id, i]));
  const nombres = nombresDisponibles(contenido, porId);
  const sueltas = contenido.variables.filter((v) => !v.pieza_id);

  function detalleVariable(v: Variable) {
    if (!v.ingresa_vendedor) return `= ${v.formula ?? ""}`;
    if (v.es_lista)
      return `lista: ${v.valores.join(", ")}${v.valor_predeterminado ? ` · ${v.valor_predeterminado}` : ""}`;
    return [
      "la carga el vendedor",
      v.minimo !== null &&
        v.maximo !== null &&
        `${textoMedida(v.minimo)} a ${textoMedida(v.maximo)} ${v.es_cantidad ? "u" : "mm"}`,
      v.formula && `predeterminado ${v.formula}`,
    ]
      .filter(Boolean)
      .join(" · ");
  }

  function tituloMaterial(m: Material) {
    if (m.tipo === "unico") return porId.get(m.insumo_id ?? "")?.nombre ?? "Sin insumo";
    const tipo = { elige_vendedor: "elige el vendedor", elige_sistema: "lo define el sistema", sigue: "sigue a otro" }[
      m.tipo
    ];
    return `${m.nombre} (${tipo})`;
  }

  function detalleMaterial(m: Material) {
    const opciones = contenido.opciones
      .filter((o) => o.material_id === m.id && !o.sigue_opcion_id)
      .map((o) => porId.get(o.insumo_id ?? "")?.nombre);
    return [
      m.medida,
      m.ancho && m.alto && `${formulaAparte(m.ancho)} × ${formulaAparte(m.alto)}`,
      m.area && `área ${m.area}`,
      m.cantidad !== "1" && `× ${formulaAparte(m.cantidad)}`,
      opciones.length > 0 && opciones.join(", "),
    ]
      .filter(Boolean)
      .join(" · ");
  }

  const filasVariables = (lista: Variable[]) =>
    lista.map((v) => (
      <Fila
        key={v.id}
        titulo={v.nombre}
        detalle={detalleVariable(v)}
        onAbrir={() => setPanel({ tipo: "variable", id: v.id, piezaId: v.pieza_id })}
        tabla="catalogo_variables"
        id={v.id}
        hermanos={lista.map((x) => x.id)}
        que={`la variable ${v.nombre}`}
      />
    ));

  const abierto = panel?.id
    ? panel.tipo === "pieza"
      ? contenido.piezas.find((p) => p.id === panel.id)
      : panel.tipo === "variable"
        ? contenido.variables.find((v) => v.id === panel.id)
        : contenido.materiales.find((m) => m.id === panel.id)
    : null;

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/catalogo/paquetes/versiones/${version.id}`}
        className="t-body-m flex items-center gap-1 text-text-brand"
      >
        <ArrowLeft size={14} strokeWidth={1.75} />
        {version.nombre} · v{version.numero}
      </Link>
      <h2 className="t-h2">Editar v{version.numero}</h2>

      {frena.length > 0 && (
        <details open={frena.length <= 3} className="rounded-md bg-warning-bg p-3 text-warning-text">
          <summary className="t-body-m tap-target cursor-pointer font-semibold">
            <TriangleAlert size={16} strokeWidth={1.75} className="mr-1 inline" />
            {frena.length === 1 ? "1 cosa frena el envío" : `${frena.length} cosas frenan el envío`}
          </summary>
          <ul className="t-body-m mt-2 list-disc pl-5">
            {frena.map((f) => (
              <li key={f}>{f}</li>
            ))}
          </ul>
        </details>
      )}

      <DatosVersion version={version} categorias={categorias} colores={colores} />

      <section className="flex flex-col gap-2">
        <h3 className="t-label">Variables por sí solas</h3>
        <p className="t-caption">De todo el paquete, fuera de toda pieza: ancho, alto.</p>
        <ul className="flex flex-col">{filasVariables(sueltas)}</ul>
        <button
          className="btn btn-secondary btn-sm self-start"
          onClick={() => setPanel({ tipo: "variable", id: null, piezaId: null })}
        >
          <Plus size={14} />
          Sumar variable
        </button>
      </section>

      <section className="flex flex-col gap-3">
        <h3 className="t-label">Piezas armadas</h3>
        {contenido.piezas.length === 0 && <p className="t-body-m">El paquete está vacío: sumá su primera pieza.</p>}
        {contenido.piezas.map((p) => {
          const variables = contenido.variables.filter((v) => v.pieza_id === p.id);
          const materiales = contenido.materiales.filter((m) => m.pieza_id === p.id);
          return (
            <div key={p.id} className="card flex flex-col gap-2">
              <ul>
                <Fila
                  titulo={p.cantidad === "1" ? p.nombre : `${p.nombre} × ${formulaAparte(p.cantidad)}`}
                  detalle={[
                    p.opcional && (p.incluida ? "opcional, incluida" : "opcional"),
                    p.secundario && "secundaria",
                    p.requiere_pieza_id &&
                      `requiere ${contenido.piezas.find((x) => x.id === p.requiere_pieza_id)?.nombre}`,
                    p.calcula_espesor && "calcula espesor",
                  ]
                    .filter(Boolean)
                    .join(" · ")}
                  onAbrir={() => setPanel({ tipo: "pieza", id: p.id })}
                  tabla="catalogo_piezas"
                  id={p.id}
                  hermanos={contenido.piezas.map((x) => x.id)}
                  que={`la pieza ${p.nombre}`}
                />
              </ul>
              <div className="flex flex-col gap-1 pl-3">
                {variables.length > 0 && (
                  <>
                    <h4 className="t-caption font-medium">Variables</h4>
                    <ul className="flex flex-col">{filasVariables(variables)}</ul>
                  </>
                )}
                <h4 className="t-caption font-medium">Materiales</h4>
                {materiales.length === 0 && <p className="t-caption text-warning-text">Sin materiales.</p>}
                <ul className="flex flex-col">
                  {materiales.map((m) => (
                    <Fila
                      key={m.id}
                      titulo={tituloMaterial(m)}
                      detalle={detalleMaterial(m)}
                      onAbrir={() => setPanel({ tipo: "material", id: m.id, piezaId: p.id })}
                      tabla="catalogo_materiales"
                      id={m.id}
                      hermanos={materiales.map((x) => x.id)}
                      que="el material"
                    />
                  ))}
                </ul>
                <div className="flex flex-wrap gap-2">
                  <button
                    className="btn btn-secondary btn-sm"
                    onClick={() => setPanel({ tipo: "material", id: null, piezaId: p.id })}
                  >
                    <Plus size={14} />
                    Material
                  </button>
                  <button
                    className="btn btn-secondary btn-sm"
                    onClick={() => setPanel({ tipo: "variable", id: null, piezaId: p.id })}
                  >
                    <Plus size={14} />
                    Variable
                  </button>
                </div>
              </div>
            </div>
          );
        })}
        <button className="btn btn-primary self-start" onClick={() => setPanel({ tipo: "pieza", id: null })}>
          <Plus size={16} />
          Sumar pieza
        </button>
      </section>

      {panel?.tipo === "pieza" && (panel.id === null || abierto) && (
        <PiezaPanel
          key={panel.id ?? "nueva"}
          versionId={version.id}
          pieza={panel.id ? (contenido.piezas.find((p) => p.id === panel.id) ?? null) : null}
          piezas={contenido.piezas}
          nombres={nombres}
          onClose={() => setPanel(null)}
        />
      )}
      {panel?.tipo === "variable" && (panel.id === null || abierto) && (
        <VariablePanel
          key={panel.id ?? "nueva"}
          versionId={version.id}
          variable={panel.id ? (contenido.variables.find((v) => v.id === panel.id) ?? null) : null}
          piezaId={panel.piezaId}
          piezas={contenido.piezas}
          orden={contenido.variables.filter((v) => v.pieza_id === panel.piezaId).length}
          condiciones={contenido.condiciones}
          nombres={nombres}
          onClose={() => setPanel(null)}
        />
      )}
      {panel?.tipo === "material" && (panel.id === null || abierto) && (
        <MaterialPanel
          key={panel.id ?? "nuevo"}
          versionId={version.id}
          material={panel.id ? (contenido.materiales.find((m) => m.id === panel.id) ?? null) : null}
          piezaId={panel.piezaId}
          orden={contenido.materiales.filter((m) => m.pieza_id === panel.piezaId).length}
          contenido={contenido}
          insumos={porId}
          nombres={nombres}
          abrirOpcion={panel.sumarOpcion}
          onCreado={(id, sumarOpcion) => setPanel({ tipo: "material", id, piezaId: panel.piezaId, sumarOpcion })}
          onClose={() => setPanel(null)}
        />
      )}
    </div>
  );
}
