"use client";

import { useState } from "react";
import { useFieldArray, useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowDown, ArrowUp, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarPlantilla } from "../actions";
import type { PlantillaCompleta } from "../queries";
import { plantillaSchema, type PlantillaForm } from "../types";
import { AsignadoSelect } from "./AsignadoSelect";
import { Campo, claseInput } from "./Campo";

const FORM_ID = "plantilla-form";

const pasoVacio = {
  titulo: "",
  descripcion: "",
  asignado_id: null,
  asignado_equipo_id: null,
  prioridad: "media" as const,
  vence_dias: "",
  espera_anterior: true,
};

export function PlantillaFormPanel({ plantilla, onClose }: { plantilla?: PlantillaCompleta; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    setValue,
    formState: { errors, isDirty },
  } = useForm<PlantillaForm>({
    resolver: zodResolver(plantillaSchema),
    defaultValues: {
      id: plantilla?.id,
      nombre: plantilla?.nombre ?? "",
      descripcion: plantilla?.descripcion ?? "",
      pasos: plantilla?.tareas_plantillas_pasos.map((p) => ({
        titulo: p.titulo,
        descripcion: p.descripcion ?? "",
        asignado_id: p.asignado_id,
        asignado_equipo_id: p.asignado_equipo_id,
        prioridad: p.prioridad,
        vence_dias: p.vence_dias ?? "",
        espera_anterior: p.espera_anterior,
      })) ?? [pasoVacio],
    },
  });
  const { fields, append, remove, move } = useFieldArray({ control, name: "pasos" });
  const pasos = useWatch({ control, name: "pasos" });

  async function onSubmit(data: PlantillaForm) {
    setEnviando(true);
    const result = await guardarPlantilla(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(plantilla ? "Plantilla guardada" : "Plantilla creada");
    onClose();
  }

  return (
    <RightPanel
      title={plantilla ? "Editar plantilla" : "Nueva plantilla"}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <div className="flex-1" />
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : plantilla ? "Guardar" : "Crear plantilla"}
          </button>
        </>
      }
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <Campo id="plantilla-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="plantilla-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>

        <Campo id="plantilla-descripcion" label="Descripción" error={errors.descripcion}>
          <textarea
            id="plantilla-descripcion"
            rows={2}
            className={claseInput(errors.descripcion)}
            {...register("descripcion")}
          />
        </Campo>

        <p className="t-label">Pasos</p>
        {errors.pasos?.root && <p className="input-error-text">{errors.pasos.root.message}</p>}

        {fields.map((f, i) => {
          const e = errors.pasos?.[i];
          const paso = pasos?.[i];
          const espera = i > 0 && paso?.espera_anterior !== false;
          return (
            <fieldset key={f.id} className="flex flex-col gap-3 rounded-lg border border-border p-3">
              <div className="flex items-center gap-1">
                <legend className="t-label flex-1">Paso {i + 1}</legend>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  aria-label="Subir"
                  disabled={i === 0}
                  onClick={() => move(i, i - 1)}
                >
                  <ArrowUp size={14} />
                </button>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm"
                  aria-label="Bajar"
                  disabled={i === fields.length - 1}
                  onClick={() => move(i, i + 1)}
                >
                  <ArrowDown size={14} />
                </button>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm text-error-text"
                  aria-label="Quitar paso"
                  disabled={fields.length === 1}
                  onClick={() => remove(i)}
                >
                  <Trash2 size={14} />
                </button>
              </div>

              <Campo id={`pp-titulo-${i}`} label="Título" requerido error={e?.titulo}>
                <input id={`pp-titulo-${i}`} aria-required className={claseInput(e?.titulo)} {...register(`pasos.${i}.titulo`)} />
              </Campo>

              <Campo id={`pp-descripcion-${i}`} label="Descripción" error={e?.descripcion}>
                <textarea
                  id={`pp-descripcion-${i}`}
                  rows={2}
                  className={claseInput(e?.descripcion)}
                  {...register(`pasos.${i}.descripcion`)}
                />
              </Campo>

              <Campo id={`pp-asignado-${i}`} label="Asignado" error={e?.asignado_id}>
                <AsignadoSelect
                  id={`pp-asignado-${i}`}
                  vacio="Se elige al usarla"
                  invalido={!!e?.asignado_id}
                  value={{ asignado_id: paso?.asignado_id ?? null, asignado_equipo_id: paso?.asignado_equipo_id ?? null }}
                  onChange={(v) => {
                    setValue(`pasos.${i}.asignado_id`, v.asignado_id, { shouldDirty: true });
                    setValue(`pasos.${i}.asignado_equipo_id`, v.asignado_equipo_id, { shouldDirty: true });
                  }}
                />
              </Campo>

              <div className="flex gap-3">
                <div className="flex-1">
                  <Campo id={`pp-prioridad-${i}`} label="Prioridad" error={e?.prioridad}>
                    <select id={`pp-prioridad-${i}`} className="input" {...register(`pasos.${i}.prioridad`)}>
                      <option value="alta">Alta</option>
                      <option value="media">Media</option>
                      <option value="baja">Baja</option>
                    </select>
                  </Campo>
                </div>
                <div className="flex-1">
                  <Campo
                    id={`pp-dias-${i}`}
                    label={espera ? "Vence a los días de habilitarse" : "Vence a los días de usarla"}
                    error={e?.vence_dias}
                  >
                    <input
                      id={`pp-dias-${i}`}
                      type="number"
                      min={1}
                      className={claseInput(e?.vence_dias)}
                      {...register(`pasos.${i}.vence_dias`)}
                    />
                  </Campo>
                </div>
              </div>

              {i > 0 && (
                <label className="t-body-m flex items-center gap-2">
                  <input type="checkbox" {...register(`pasos.${i}.espera_anterior`)} />
                  Espera al paso anterior
                </label>
              )}
            </fieldset>
          );
        })}

        <button type="button" className="btn btn-secondary btn-sm self-start" onClick={() => append(pasoVacio)}>
          <Plus size={14} />
          Sumar paso
        </button>
      </form>
    </RightPanel>
  );
}
