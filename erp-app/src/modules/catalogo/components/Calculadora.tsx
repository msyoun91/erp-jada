"use client";

import { useState, useTransition } from "react";
import { toast } from "sonner";
import { claseInput } from "@/components/ui/Campo";
import { MONEDAS, MONEDAS_LISTA, type Moneda } from "@/lib/monedas";
import { calcular } from "../actions";
import { aEntrada, desdeEntrada, ESTADO_VACIO, type EntradaEstado } from "../entrada";
import { textoMedida } from "../etiquetas";
import type { Caso, ColorVersion, Contenido, Despiece, PrecioDetalle } from "../types";
import { DespieceResultado } from "./DespieceResultado";

// Lo que cargaría un vendedor, para ver el despiece (y con `catalogo_aprobar`, el precio) de cualquier
// versión. No guarda nada: los casos de prueba se cargan en el editor.
export function Calculadora({
  versionId,
  contenido,
  colores,
  nombreInsumo,
  inicial,
  puedeAprobar,
  monedaPrincipal,
  comparar,
}: {
  versionId: string;
  contenido: Contenido;
  colores: ColorVersion[];
  nombreInsumo: Map<string, string>;
  inicial: { caso: Caso | null; resultado: Despiece | null; comparado: PrecioDetalle | null };
  puedeAprobar: boolean;
  monedaPrincipal: Moneda;
  comparar: { id: string; numero: number } | null;
}) {
  const [estado, setEstado] = useState<EntradaEstado>(
    inicial.caso ? desdeEntrada(inicial.caso.entrada, contenido) : ESTADO_VACIO,
  );
  const [casoId, setCasoId] = useState(inicial.caso?.id ?? "");
  const [resultado, setResultado] = useState(inicial.resultado);
  const [comparado, setComparado] = useState(inicial.comparado);
  const [moneda, setMoneda] = useState<Moneda>(monedaPrincipal);
  const [opcionales, setOpcionales] = useState<string[]>([]);
  const [pendiente, startTransition] = useTransition();
  const nombrePieza = new Map(contenido.piezas.map((p) => [p.id, p.nombre]));

  function correr(e: EntradaEstado, m = moneda, o = opcionales) {
    startTransition(async () => {
      const r = await calcular({
        version_id: versionId,
        entrada: aEntrada(e, contenido),
        precio: puedeAprobar ? { moneda: m, opcionales: o, comparar_con: comparar?.id ?? null } : null,
      });
      if (!r.success) {
        toast.error(r.error);
        return;
      }
      setResultado(r.resultado);
      setComparado(r.comparado);
    });
  }

  function elegirCaso(id: string) {
    setCasoId(id);
    const caso = contenido.casos.find((c) => c.id === id);
    const e = caso ? desdeEntrada(caso.entrada, contenido) : ESTADO_VACIO;
    setEstado(e);
    correr(e);
  }

  const set = <K extends keyof EntradaEstado>(k: K, id: string, valor: string) =>
    setEstado((e) => ({ ...e, [k]: { ...(e[k] as Record<string, string>), [id]: valor } }));

  const variables = contenido.variables.filter((v) => v.ingresa_vendedor);
  const piezas = contenido.piezas.filter((p) => p.opcional);
  const elegibles = contenido.materiales.filter((m) => m.tipo === "elige_vendedor");
  const serviciosOpcionales =
    resultado && "servicios" in resultado ? (resultado as PrecioDetalle).servicios.filter((s) => s.opcional) : [];

  return (
    <div className="grid gap-6 lg:grid-cols-[minmax(0,320px)_1fr]">
      <form
        className="flex flex-col gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          correr(estado);
        }}
      >
        {contenido.casos.length > 0 && (
          <label className="flex flex-col gap-1">
            <span className="t-label">Caso de prueba</span>
            <select className="input" value={casoId} onChange={(e) => elegirCaso(e.target.value)}>
              <option value="">Ninguno: todo predeterminado</option>
              {contenido.casos.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nombre}
                </option>
              ))}
            </select>
          </label>
        )}

        {variables.map((v) => (
          <label key={v.id} className="flex flex-col gap-1">
            <span className="t-label">
              {v.nombre}
              {v.es_lista ? "" : v.es_cantidad ? " (u)" : " (mm)"}
              {v.pieza_id ? ` · ${nombrePieza.get(v.pieza_id)}` : ""}
            </span>
            {v.es_lista ? (
              <select
                className="input"
                value={estado.variables[v.id] ?? ""}
                onChange={(e) => set("variables", v.id, e.target.value)}
              >
                <option value="">
                  {v.valor_predeterminado ? `Predeterminado: ${v.valor_predeterminado}` : "Sin elegir"}
                </option>
                {v.valores.map((x) => (
                  <option key={x} value={x}>
                    {x}
                  </option>
                ))}
              </select>
            ) : (
              <input
                className={claseInput()}
                inputMode="decimal"
                value={estado.variables[v.id] ?? ""}
                placeholder={v.formula ? `Predeterminado: ${v.formula}` : "Obligatoria"}
                onChange={(e) => set("variables", v.id, e.target.value)}
              />
            )}
            {v.minimo !== null && v.maximo !== null && (
              <span className="t-caption">
                De {textoMedida(v.minimo)} a {textoMedida(v.maximo)}
              </span>
            )}
          </label>
        ))}

        {elegibles.map((m) => {
          const opciones = contenido.opciones.filter((o) => o.material_id === m.id && o.insumo_id);
          const pred = opciones.find((o) => o.predeterminada);
          return (
            <label key={m.id} className="flex flex-col gap-1">
              <span className="t-label">
                {m.nombre} · {nombrePieza.get(m.pieza_id)}
              </span>
              <select
                className="input"
                value={estado.elecciones[m.id] ?? ""}
                onChange={(e) => set("elecciones", m.id, e.target.value)}
              >
                <option value="">
                  {pred ? `Predeterminada: ${nombreInsumo.get(pred.insumo_id ?? "")}` : "Sin predeterminada"}
                </option>
                {opciones.map((o) => (
                  <option key={o.id} value={o.insumo_id ?? ""}>
                    {nombreInsumo.get(o.insumo_id ?? "")}
                  </option>
                ))}
                {m.sin_eleccion && <option value="ninguna">Sin elección</option>}
              </select>
            </label>
          );
        })}

        {piezas.map((p) => (
          <label key={p.id} className="flex flex-col gap-1">
            <span className="t-label">{p.nombre} (opcional)</span>
            <select
              className="input"
              value={estado.piezas[p.id] ?? ""}
              onChange={(e) => set("piezas", p.id, e.target.value)}
            >
              <option value="">Predeterminado: {p.incluida ? "incluida" : "sin incluir"}</option>
              <option value="si">Incluida</option>
              <option value="no">Sin incluir</option>
            </select>
          </label>
        ))}

        {colores.length > 0 && (
          <label className="flex flex-col gap-1">
            <span className="t-label">Color</span>
            <select
              className="input"
              value={estado.color}
              onChange={(e) => setEstado((x) => ({ ...x, color: e.target.value }))}
            >
              <option value="">Base: {colores.find((c) => c.base)?.nombre ?? "sin base"}</option>
              {colores.map((c) => (
                <option key={c.color_id} value={c.color_id}>
                  {c.nombre}
                </option>
              ))}
            </select>
          </label>
        )}

        {puedeAprobar && (
          <>
            <label className="flex flex-col gap-1">
              <span className="t-label">Moneda del precio</span>
              <select className="input" value={moneda} onChange={(e) => setMoneda(e.target.value as Moneda)}>
                {MONEDAS_LISTA.map((x) => (
                  <option key={x} value={x}>
                    {MONEDAS[x]}
                  </option>
                ))}
              </select>
            </label>
            {serviciosOpcionales.map((s) => (
              <label key={s.porcentaje_id} className="tap-target flex items-center gap-2">
                <input
                  type="checkbox"
                  checked={opcionales.includes(s.porcentaje_id)}
                  onChange={(e) =>
                    setOpcionales((o) =>
                      e.target.checked ? [...o, s.porcentaje_id] : o.filter((x) => x !== s.porcentaje_id),
                    )
                  }
                />
                <span className="t-body-m">{s.nombre} (opcional)</span>
              </label>
            ))}
          </>
        )}

        <button type="submit" className="btn btn-primary" disabled={pendiente}>
          {pendiente ? "Calculando…" : "Calcular"}
        </button>
      </form>

      <div className={pendiente ? "opacity-60" : ""}>
        {resultado ? (
          <DespieceResultado resultado={resultado} comparado={comparado} numeroComparado={comparar?.numero ?? null} />
        ) : (
          <p className="t-body-m">Cargá las medidas y tocá Calcular.</p>
        )}
      </div>
    </div>
  );
}
