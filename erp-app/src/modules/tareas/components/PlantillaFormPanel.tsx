"use client";

import { useState } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { ChevronDown, ChevronUp, Plus, X } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearPlantilla, editarPlantilla } from "../actions";
import { crearPlantillaSchema, type CrearPlantillaForm } from "../types";
import type { TareaPlantilla, TareaPlantillaItem } from "../types";

// Con `plantilla` presente pasa a modo edición. Mismo schema para los dos:
// los pasos existentes viajan con su `id` (se actualizan), los nuevos sin él.
export function PlantillaFormPanel({
  plantilla,
  items,
  onClose,
}: {
  plantilla?: TareaPlantilla;
  items?: TareaPlantillaItem[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<CrearPlantillaForm>({
    resolver: zodResolver(crearPlantillaSchema),
    defaultValues: plantilla
      ? {
          nombre: plantilla.nombre,
          descripcion: plantilla.descripcion ?? undefined,
          items: (items ?? []).map((item, i) => ({ id: item.id, titulo: item.titulo, orden: i })),
        }
      : { items: [{ titulo: "", orden: 0 }] },
  });
  const { fields, append, remove, move } = useFieldArray({ control, name: "items" });

  async function onSubmit(data: CrearPlantillaForm) {
    // El orden se toma de la posición en el form, no de un campo editable.
    const conOrden = { ...data, items: data.items.map((item, i) => ({ ...item, orden: i })) };
    setEnviando(true);
    const result = plantilla
      ? await editarPlantilla({ ...conOrden, id: plantilla.id })
      : await crearPlantilla(conOrden);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(plantilla ? "Plantilla actualizada" : "Plantilla creada");
    onClose();
  }

  return (
    <RightPanel
      title={plantilla ? "Editar plantilla" : "Nueva plantilla"}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-plantilla" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : plantilla ? "Guardar" : "Crear plantilla"}
          </button>
        </>
      }
    >
      <form
        id="form-plantilla"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Nombre</label>
          <input
            aria-required
            className={`input ${errors.nombre ? "input-error" : ""}`}
            {...register("nombre")}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea rows={2} className="input" {...register("descripcion")} />
        </div>

        {plantilla && (
          <p className="t-caption">
            Los cambios aplican a los próximos usos — las tareas ya generadas desde esta plantilla no se tocan.
          </p>
        )}

        <div>
          <label className="t-label t-label-req mb-1 block">Pasos</label>
          <p className="t-caption mb-2">
            El orden manda: al usar la plantilla, cada paso se habilita al completar el anterior.
          </p>
          <div className="flex flex-col gap-2">
            {fields.map((field, i) => (
              <div key={field.id} className="flex items-center gap-2">
                <input
                  aria-required
                  className={`input ${errors.items?.[i]?.titulo ? "input-error" : ""}`}
                  {...register(`items.${i}.titulo` as const)}
                />
                {/* El orden encadena los pasos (cada uno espera al anterior):
                    sin mover no quedaba forma de corregirlo salvo retipear
                    todos los títulos de ahí para abajo. */}
                <button
                  type="button"
                  className="btn btn-ghost btn-sm shrink-0"
                  onClick={() => move(i, i - 1)}
                  disabled={i === 0}
                  aria-label="Subir paso"
                >
                  <ChevronUp size={14} />
                </button>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm shrink-0"
                  onClick={() => move(i, i + 1)}
                  disabled={i === fields.length - 1}
                  aria-label="Bajar paso"
                >
                  <ChevronDown size={14} />
                </button>
                <button
                  type="button"
                  className="btn btn-ghost btn-sm shrink-0"
                  onClick={() => remove(i)}
                  disabled={fields.length === 1}
                  aria-label="Quitar paso"
                >
                  <X size={14} />
                </button>
              </div>
            ))}
          </div>
          {errors.items && !Array.isArray(errors.items) && (
            <p className="input-error-text">{errors.items.message}</p>
          )}
          <button
            type="button"
            className="btn btn-ghost btn-sm mt-2"
            onClick={() => append({ titulo: "", orden: fields.length })}
          >
            <Plus size={14} />
            Agregar paso
          </button>
        </div>
      </form>
    </RightPanel>
  );
}
