"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarValorVariable, guardarVariable, sacar } from "../../actions";
import {
  variableSchema,
  type Contenido,
  type Material,
  type Opcion,
  type ValorVariable,
  type Variable,
  type VariableForm,
} from "../../types";
import { CondicionesLista } from "./CondicionesLista";
import type { InsumosPorId } from "./InsumoSelect";
import { Nombres } from "./Nombres";

const numeroONulo = (v: unknown) => (v === "" || v === null ? null : Number(v));

// Solo decide si se muestra el campo: lo que frena el envío lo decide la base (`catalogo_version_referencias`).
function puedeQuedarSinEleccion(m: Material, contenido: Contenido) {
  const elige = (x: Material | undefined) => Boolean(x?.sin_eleccion || /\bninguno\b/.test(x?.eleccion ?? ""));
  if (m.tipo !== "sigue") return elige(m);
  return (
    elige(contenido.materiales.find((x) => x.id === m.sigue_material_id)) ||
    contenido.opciones.some((o) => o.material_id === m.id && !o.insumo_id)
  );
}

// El nombre es el que lee el vendedor y el que usan las fórmulas (`[Ancho de hoja 1]`).
export function VariablePanel({
  versionId,
  variable,
  piezaId,
  orden,
  contenido,
  insumos,
  nombres,
  onCreado,
  onClose,
}: {
  versionId: string;
  variable: Variable | null;
  piezaId: string | null;
  orden: number;
  contenido: Contenido;
  insumos: InsumosPorId;
  nombres: string[];
  onCreado: (id: string) => void;
  onClose: () => void;
}) {
  const { register, handleSubmit, control, formState, getValues, reset } = useForm<VariableForm>({
    resolver: zodResolver(variableSchema),
    defaultValues: variable
      ? { ...variable, version_id: versionId, valores: variable.valores.join("\n") }
      : {
          id: null,
          version_id: versionId,
          orden,
          pieza_id: piezaId,
          nombre: "",
          ingresa_vendedor: true,
          es_lista: false,
          formula: null,
          valores: "",
          valor_predeterminado: null,
          es_cantidad: false,
          minimo: null,
          maximo: null,
          secundario: false,
          a_produccion: true,
          segun_material_id: null,
        },
  });
  const { errors, isSubmitting } = formState;
  const [ingresa, lista, segunId] = useWatch({ control, name: ["ingresa_vendedor", "es_lista", "segun_material_id"] });
  const segun = !ingresa && segunId ? segunId : null;
  const materiales = contenido.materiales.filter((m) => m.tipo !== "unico");
  const nombrePieza = (id: string) => contenido.piezas.find((p) => p.id === id)?.nombre;
  const materialGuardado =
    variable?.segun_material_id === segun ? materiales.find((m) => m.id === segun) : undefined;
  const materialSegun = materiales.find((m) => m.id === segun);
  // Lo ya cargado se ve aunque el material ya no pueda quedar vacío: la base lo sigue revisando.
  const conSinEleccion =
    materialSegun && (puedeQuedarSinEleccion(materialSegun, contenido) || Boolean(getValues("formula")));

  async function guardar(d: VariableForm) {
    const r = await guardarVariable(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(variable ? "Variable guardada" : `Se sumó ${d.nombre}`);
    // Los valores cuelgan de la variable guardada y de ese material: el panel sigue abierto para cargarlos.
    const material = !d.ingresa_vendedor && d.segun_material_id;
    if (!material || material === variable?.segun_material_id) onClose();
    else if (variable) reset(getValues());
    else onCreado(r.id);
  }

  return (
    <RightPanel
      title={variable ? `Variable ${variable.nombre}` : "Nueva variable"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <button className="btn btn-primary" onClick={handleSubmit(guardar)} disabled={isSubmitting}>
          Guardar
        </button>
      }
    >
      <div className="flex flex-col gap-4 overflow-y-auto p-5">
        <form onSubmit={handleSubmit(guardar)} className="flex flex-col gap-4">
          <Campo id="var-nombre" label="Nombre" requerido error={errors.nombre}>
            <input id="var-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
          </Campo>
          <Campo id="var-pieza" label="Dónde está" error={errors.pieza_id}>
            <select id="var-pieza" className="input" {...register("pieza_id")}>
              <option value="">Por sí sola (de todo el paquete)</option>
              {contenido.piezas.map((p) => (
                <option key={p.id} value={p.id}>
                  En {p.nombre}
                </option>
              ))}
            </select>
          </Campo>

          <label className="tap-target flex items-center gap-2">
            <input type="checkbox" {...register("ingresa_vendedor")} />
            <span className="t-body-m">La carga el vendedor</span>
          </label>

          {ingresa && (
            <label className="tap-target flex items-start gap-2">
              <input type="checkbox" className="mt-1" {...register("es_lista")} />
              <span className="t-body-m">
                Lista de valores
                <span className="t-caption block">Como la mano de una puerta. No entra en las cuentas.</span>
              </span>
            </label>
          )}

          {!ingresa && (
            <Campo id="var-segun" label="De dónde sale" error={errors.segun_material_id}>
              <select id="var-segun" className="input" {...register("segun_material_id")}>
                <option value="">De una fórmula</option>
                {materiales.map((m) => (
                  <option key={m.id} value={m.id}>
                    Según {m.nombre} · {nombrePieza(m.pieza_id)}
                  </option>
                ))}
              </select>
            </Campo>
          )}

          {segun ? (
            conSinEleccion && (
              <Campo id="var-formula" label="Si no hay elección (número o fórmula)" requerido error={errors.formula}>
                <input
                  id="var-formula"
                  aria-required
                  className={`${claseInput(errors.formula)} font-mono`}
                  {...register("formula")}
                />
              </Campo>
            )
          ) : ingresa && lista ? (
            <>
              <Campo id="var-valores" label="Valores, uno por renglón" error={errors.valores}>
                <textarea id="var-valores" rows={4} className={claseInput(errors.valores)} {...register("valores")} />
              </Campo>
              <Campo id="var-pred" label="Predeterminado (vacío: obligatoria)" error={errors.valor_predeterminado}>
                <input id="var-pred" className="input" {...register("valor_predeterminado")} />
              </Campo>
            </>
          ) : (
            <Campo
              id="var-formula"
              label={ingresa ? "Predeterminado, con fórmula (vacío: obligatoria)" : "Fórmula"}
              requerido={!ingresa}
              error={errors.formula}
            >
              <input
                id="var-formula"
                aria-required={!ingresa}
                className={`${claseInput(errors.formula)} font-mono`}
                {...register("formula")}
              />
            </Campo>
          )}
          {!segun && !(ingresa && lista) && <Nombres nombres={nombres} />}

          {ingresa && !lista && (
            <>
              <Campo id="var-es-cantidad" label="Qué es" error={errors.es_cantidad}>
                <select
                  id="var-es-cantidad"
                  className="input"
                  {...register("es_cantidad", { setValueAs: (v) => v === true || v === "true" })}
                >
                  <option value="false">Una medida (mm)</option>
                  <option value="true">Una cantidad (u)</option>
                </select>
              </Campo>
              <div className="grid grid-cols-2 gap-3">
                <Campo id="var-min" label="Mínimo" requerido error={errors.minimo}>
                  <input
                    id="var-min"
                    type="number"
                    step="any"
                    aria-required
                    className={claseInput(errors.minimo)}
                    {...register("minimo", { setValueAs: numeroONulo })}
                  />
                </Campo>
                <Campo id="var-max" label="Máximo" requerido error={errors.maximo}>
                  <input
                    id="var-max"
                    type="number"
                    step="any"
                    aria-required
                    className={claseInput(errors.maximo)}
                    {...register("maximo", { setValueAs: numeroONulo })}
                  />
                </Campo>
              </div>
              <p className="t-caption">Fuera de rango bloquea, también si sale del predeterminado.</p>
            </>
          )}

          {ingresa && (
            <label className="tap-target flex items-center gap-2">
              <input type="checkbox" {...register("secundario")} />
              <span className="t-body-m">Secundaria: va plegada en &quot;Más opciones&quot; (pide predeterminado)</span>
            </label>
          )}
          <label className="tap-target flex items-center gap-2">
            <input type="checkbox" {...register("a_produccion")} />
            <span className="t-body-m">Pasa a Producción</span>
          </label>
        </form>

        {segun &&
          (variable && materialGuardado ? (
            <Valores
              versionId={versionId}
              variable={variable}
              material={materialGuardado}
              contenido={contenido}
              insumos={insumos}
              nombres={nombres}
            />
          ) : (
            <p className="t-caption">Al guardar se cargan los valores, uno por cada opción de ese material.</p>
          ))}

        {variable && (
          <CondicionesLista
            versionId={versionId}
            de={{ variable_id: variable.id }}
            condiciones={contenido.condiciones}
          />
        )}
      </div>
    </RightPanel>
  );
}

// Un valor por cada opción del material, "ninguna" no: esa la cubre "Si no hay elección".
function Valores({
  versionId,
  variable,
  material,
  contenido,
  insumos,
  nombres,
}: {
  versionId: string;
  variable: Variable;
  material: Material;
  contenido: Contenido;
  insumos: InsumosPorId;
  nombres: string[];
}) {
  const nombreInsumo = (id: string | null) => insumos.get(id ?? "")?.nombre ?? "—";
  const opciones = contenido.opciones.filter((o) => o.material_id === material.id && o.insumo_id);

  // Dos opciones del que elige pueden tener la misma pareja, y cada fila lleva su valor.
  function etiqueta(o: Opcion) {
    if (material.tipo !== "sigue") return nombreInsumo(o.insumo_id);
    if (!o.sigue_opcion_id) return `${nombreInsumo(o.insumo_id)} · suelta`;
    const delQueElige = contenido.opciones.find((x) => x.id === o.sigue_opcion_id);
    return `${nombreInsumo(o.insumo_id)} · con ${nombreInsumo(delQueElige?.insumo_id ?? null)}`;
  }

  return (
    <section className="flex flex-col gap-2">
      <h4 className="t-label">Valor según {material.nombre}</h4>
      {opciones.length === 0 ? (
        <p className="t-body-m text-warning-text">{material.nombre} todavía no tiene opciones.</p>
      ) : (
        <>
          <p className="t-caption">Número o fórmula. Se guarda al salir del campo; una opción sin valor frena el envío.</p>
          <ul className="flex flex-col gap-2">
            {opciones.map((o) => (
              <ValorFila
                key={o.id}
                versionId={versionId}
                variableId={variable.id}
                opcionId={o.id}
                etiqueta={etiqueta(o)}
                valor={contenido.valores.find((x) => x.variable_id === variable.id && x.opcion_id === o.id)}
              />
            ))}
          </ul>
          <Nombres nombres={nombres.filter((n) => n !== variable.nombre)} />
        </>
      )}
    </section>
  );
}

function ValorFila({
  versionId,
  variableId,
  opcionId,
  etiqueta,
  valor,
}: {
  versionId: string;
  variableId: string;
  opcionId: string;
  etiqueta: string;
  valor: ValorVariable | undefined;
}) {
  const [texto, setTexto] = useState(valor?.formula ?? "");
  const id = `valor-${opcionId}`;

  async function guardar() {
    const nuevo = texto.trim();
    if (nuevo === (valor?.formula ?? "")) return;
    if (!nuevo && !valor) return;
    const r = nuevo
      ? await guardarValorVariable({
          id: valor?.id ?? null,
          version_id: versionId,
          variable_id: variableId,
          opcion_id: opcionId,
          formula: nuevo,
        })
      : await sacar({ tabla: "catalogo_variables_valores", id: valor!.id });
    if (!r.success) toast.error(r.error);
  }

  return (
    <li className="flex flex-col gap-1">
      <label htmlFor={id} className="t-body-m">
        {etiqueta}
      </label>
      <input
        id={id}
        className="input font-mono"
        value={texto}
        onChange={(e) => setTexto(e.target.value)}
        onBlur={guardar}
      />
    </li>
  );
}
