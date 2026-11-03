"use client";

import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Ayuda } from "@/components/ui/Ayuda";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarVariable } from "../../actions";
import { EJEMPLO } from "../../ejemplos";
import { variableSchema, type Condicion, type Pieza, type Variable, type VariableForm } from "../../types";
import { CondicionesLista } from "./CondicionesLista";
import { Nombres } from "./Nombres";

const numeroONulo = (v: unknown) => (v === "" || v === null ? null : Number(v));

// El nombre es el que lee el vendedor y el que usan las fórmulas (`[Ancho de hoja 1]`).
export function VariablePanel({
  versionId,
  variable,
  piezaId,
  piezas,
  orden,
  condiciones,
  nombres,
  onClose,
}: {
  versionId: string;
  variable: Variable | null;
  piezaId: string | null;
  piezas: Pieza[];
  orden: number;
  condiciones: Condicion[];
  nombres: string[];
  onClose: () => void;
}) {
  const { register, handleSubmit, control, formState } = useForm<VariableForm>({
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
        },
  });
  const { errors, isSubmitting } = formState;
  const [ingresa, lista] = useWatch({ control, name: ["ingresa_vendedor", "es_lista"] });

  async function guardar(d: VariableForm) {
    const r = await guardarVariable(d);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(variable ? "Variable guardada" : `Se sumó ${d.nombre}`);
    onClose();
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
          <Campo id="var-nombre" label="Nombre" requerido error={errors.nombre} ejemplo={EJEMPLO.variableNombre}>
            <input id="var-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
          </Campo>
          <Campo id="var-pieza" label="Dónde está" error={errors.pieza_id}>
            <select id="var-pieza" className="input" {...register("pieza_id")}>
              <option value="">Por sí sola (de todo el paquete)</option>
              {piezas.map((p) => (
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
            <Ayuda de="Lista de valores" ejemplo={EJEMPLO.lista}>
              <label className="tap-target flex items-start gap-2">
                <input type="checkbox" className="mt-1" {...register("es_lista")} />
                <span className="t-body-m">
                  Lista de valores
                  <span className="t-caption block">Como la mano de una puerta. No entra en las cuentas.</span>
                </span>
              </label>
            </Ayuda>
          )}

          {ingresa && lista ? (
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
              ejemplo={ingresa ? EJEMPLO.predeterminado : EJEMPLO.formula}
            >
              <input
                id="var-formula"
                aria-required={!ingresa}
                className={`${claseInput(errors.formula)} font-mono`}
                {...register("formula")}
              />
            </Campo>
          )}
          <Nombres nombres={nombres} />

          {ingresa && !lista && (
            <>
              <Campo id="var-es-cantidad" label="Qué es" error={errors.es_cantidad} ejemplo={EJEMPLO.queEs}>
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
              <Ayuda de="Mínimo y máximo" ejemplo={EJEMPLO.rango}>
                <p className="t-caption">Fuera de rango bloquea, también si sale del predeterminado.</p>
              </Ayuda>
            </>
          )}

          {ingresa && (
            <Ayuda de="Secundaria" ejemplo={EJEMPLO.secundaria}>
              <label className="tap-target flex items-center gap-2">
                <input type="checkbox" {...register("secundario")} />
                <span className="t-body-m">
                  Secundaria: va plegada en &quot;Más opciones&quot; (pide predeterminado)
                </span>
              </label>
            </Ayuda>
          )}
          <label className="tap-target flex items-center gap-2">
            <input type="checkbox" {...register("a_produccion")} />
            <span className="t-body-m">Pasa a Producción</span>
          </label>
        </form>

        {variable && (
          <CondicionesLista versionId={versionId} de={{ variable_id: variable.id }} condiciones={condiciones} />
        )}
      </div>
    </RightPanel>
  );
}
