"use client";

import { useState } from "react";
import { ChevronRight } from "lucide-react";
import { toast } from "sonner";
import { claseInput, Etiqueta } from "@/components/ui/Campo";
import {
  colorDe,
  conPieza,
  fueraDe,
  incluida,
  malEscrita,
  textoMedida,
  type EntradaEstado,
  type FormularioEntrada,
} from "@/lib/entrada";

// Lo que carga el vendedor de un paquete: en la calculadora de Catálogo y en el renglón de un presupuesto. Lo secundario
// va plegado en "Más opciones", con su predeterminado (`decisiones/catalogo/paquete.md`). Quien lo usa le pone `key` por
// versión, así "Más opciones" arranca abierto si algo de adentro ya tiene valor.
export function EntradaCampos({
  formulario: f,
  estado,
  onChange,
}: {
  formulario: FormularioEntrada;
  estado: EntradaEstado;
  onChange: (e: EntradaEstado) => void;
}) {
  const nombrePieza = new Map(f.piezas.map((p) => [p.id, p.nombre]));
  const color = colorDe(f, estado);
  const fuera = fueraDe(f, color);
  const elegibles = f.materiales.filter((m) => m.tipo === "elige_vendedor" || m.tipo === "sigue");
  const opcionales = f.piezas.filter((p) => p.opcional);
  const [abierto] = useState(
    () =>
      f.variables.some((v) => v.secundario && estado.variables[v.id]) ||
      elegibles.some((m) => m.secundario && estado.elecciones[m.id]) ||
      opcionales.some((p) => p.secundario && estado.piezas[p.id]),
  );

  const setVariable = (id: string, valor: string) =>
    onChange({ ...estado, variables: { ...estado.variables, [id]: valor } });
  const setEleccion = (id: string, valor: string) =>
    onChange({ ...estado, elecciones: { ...estado.elecciones, [id]: valor } });

  function setPieza(id: string, valor: "" | "si" | "no") {
    const r = conPieza(f, estado, id, valor);
    if (r.aviso) toast.info(r.aviso);
    onChange(r.estado);
  }

  function setColor(id: string) {
    const r = alColor(f, estado, id);
    for (const aviso of r.avisos) toast.info(aviso);
    onChange(r.estado);
  }

  const campoVariable = (v: FormularioEntrada["variables"][number]) => (
    <label key={v.id} className="flex flex-col gap-1">
      <span className="t-label">
        <Etiqueta
          texto={`${v.nombre}${v.es_lista ? "" : v.es_cantidad ? " (u)" : " (mm)"}${v.pieza_id ? ` · ${nombrePieza.get(v.pieza_id)}` : ""}`}
        />
      </span>
      {v.es_lista ? (
        <select className="input" value={estado.variables[v.id] ?? ""} onChange={(e) => setVariable(v.id, e.target.value)}>
          <option value="">{v.predeterminado ? `Predeterminado: ${v.predeterminado}` : "Sin elegir"}</option>
          {v.valores.map((x) => (
            <option key={x} value={x}>
              {x}
            </option>
          ))}
        </select>
      ) : (
        <input
          type="text"
          className={malEscrita(v, estado) ? "input input-error" : claseInput()}
          inputMode="decimal"
          value={estado.variables[v.id] ?? ""}
          placeholder={v.predeterminado ? `Predeterminado: ${v.predeterminado}` : "Obligatoria"}
          onChange={(e) => setVariable(v.id, e.target.value)}
        />
      )}
      {malEscrita(v, estado) && (
        <span className="input-error-text">Va sin puntos y con coma para el decimal: 1500 o 1500,5</span>
      )}
      {v.minimo !== null && v.maximo !== null && (
        <span className="t-caption">
          De {textoMedida(v.minimo)} a {textoMedida(v.maximo)}
        </span>
      )}
    </label>
  );

  const campoMaterial = (m: FormularioEntrada["materiales"][number]) => {
    const propias = f.opciones.filter((o) => o.material_id === m.id);
    // Dos opciones del que elige pueden tener la misma pareja: el vendedor elige el insumo, una sola vez.
    const opciones = [...new Map(propias.filter((o) => o.insumo_id).map((o) => [o.insumo_id, o])).values()];
    const pred = opciones.find((o) => o.predeterminada);
    const sigue = m.tipo === "sigue";
    return (
      <label key={m.id} className="flex flex-col gap-1">
        <span className="t-label">
          {m.nombre} · {nombrePieza.get(m.pieza_id)}
        </span>
        <select className="input" value={estado.elecciones[m.id] ?? ""} onChange={(e) => setEleccion(m.id, e.target.value)}>
          <option value="">
            {sigue ? "La pareja de lo elegido" : pred ? `Predeterminada: ${pred.nombre}` : "Sin predeterminada"}
          </option>
          {opciones.map((o) => (
            <option key={o.id} value={o.insumo_id ?? ""} disabled={fuera.opciones.has(o.id)}>
              {o.nombre}
              {fuera.opciones.has(o.id) ? " (no en este color)" : ""}
            </option>
          ))}
          {m.sin_eleccion && <option value="ninguna">Sin elección</option>}
          {sigue && propias.some((o) => !o.insumo_id) && <option value="ninguna">Ninguna</option>}
        </select>
      </label>
    );
  };

  const campoPieza = (p: FormularioEntrada["piezas"][number]) => (
    <label key={p.id} className="flex flex-col gap-1">
      <span className="t-label">
        <Etiqueta texto={`${p.nombre} (opcional)`} />
      </span>
      <select
        className="input"
        value={estado.piezas[p.id] ?? ""}
        onChange={(e) => setPieza(p.id, e.target.value as "" | "si" | "no")}
      >
        <option value="">Predeterminado: {p.incluida ? "incluida" : "sin incluir"}</option>
        <option value="si" disabled={fuera.piezas.has(p.id)}>
          Incluida
        </option>
        <option value="no">Sin incluir</option>
      </select>
      {fuera.piezas.has(p.id) && <span className="t-caption">No se ofrece en este color.</span>}
    </label>
  );

  const secundarios = [
    ...f.variables.filter((v) => v.secundario).map(campoVariable),
    ...elegibles.filter((m) => m.secundario).map(campoMaterial),
    ...opcionales.filter((p) => p.secundario).map(campoPieza),
  ];
  const base = f.colores.find((c) => c.base);

  return (
    <>
      {f.variables.filter((v) => !v.secundario).map(campoVariable)}
      {elegibles.filter((m) => !m.secundario).map(campoMaterial)}
      {opcionales.filter((p) => !p.secundario).map(campoPieza)}
      {f.colores.length > 0 && (
        <label className="flex flex-col gap-1">
          <span className="t-label">Color</span>
          <select className="input" value={estado.color} onChange={(e) => setColor(e.target.value)}>
            <option value="">{base ? `Base: ${base.nombre}` : "Sin elegir"}</option>
            {f.colores.map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
              </option>
            ))}
          </select>
        </label>
      )}
      {secundarios.length > 0 && (
        <details open={abierto} className="group">
          <summary className="tap-target flex cursor-pointer list-none items-center gap-1 rounded-md hover:bg-bg-subtle [&::-webkit-details-marker]:hidden">
            <ChevronRight size={16} className="shrink-0 text-text-secondary transition-transform group-open:rotate-90" />
            <span className="t-label text-text-secondary">Más opciones ({secundarios.length})</span>
          </summary>
          <div className="mt-2 flex flex-col gap-3">{secundarios}</div>
        </details>
      )}
    </>
  );
}

// La base no corrige lo elegido: una pieza incluida o una opción que no se ofrece en el color nuevo se saca acá, con aviso.
function alColor(f: FormularioEntrada, e: EntradaEstado, id: string) {
  const estado: EntradaEstado = { ...e, color: id, piezas: { ...e.piezas }, elecciones: { ...e.elecciones } };
  const color = colorDe(f, estado);
  const fuera = fueraDe(f, color);
  const piezas = f.piezas.filter((p) => p.opcional && fuera.piezas.has(p.id) && incluida(p, estado));
  for (const p of piezas) estado.piezas[p.id] = "no";
  const materiales = f.materiales.filter((m) =>
    f.opciones.some(
      (o) => o.material_id === m.id && o.insumo_id && o.insumo_id === estado.elecciones[m.id] && fuera.opciones.has(o.id),
    ),
  );
  for (const m of materiales) estado.elecciones[m.id] = "";
  const nombre = color?.nombre ?? "este color";
  const avisos = [
    piezas.length ? `En ${nombre} no se ofrece ${piezas.map((p) => p.nombre).join(" ni ")}: quedó sin incluir.` : null,
    materiales.length
      ? `En ${nombre} no se ofrece lo elegido en ${materiales.map((m) => m.nombre).join(" ni ")}: vuelve a la predeterminada.`
      : null,
  ].filter((a): a is string => a !== null);
  return { estado, avisos };
}
