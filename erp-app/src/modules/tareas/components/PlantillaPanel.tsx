"use client";

import { useState } from "react";
import { useFieldArray, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { actualizarPlantilla, crearPlantilla } from "../actions";
import { crearPlantillaSchema, type CrearPlantillaForm, type TareaPlantilla } from "../types";

export function PlantillaPanel({
  plantilla,
  onClose,
}: {
  plantilla: TareaPlantilla | null;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);

  const {
    register,
    control,
    handleSubmit,
    formState: { errors },
  } = useForm<CrearPlantillaForm>({
    resolver: zodResolver(crearPlantillaSchema),
    defaultValues: plantilla
      ? { nombre: plantilla.nombre, items: plantilla.items.map((i) => ({ titulo: i.titulo, descripcion: i.descripcion ?? "" })) }
      : { nombre: "", items: [{ titulo: "", descripcion: "" }] },
  });

  const { fields, append, remove } = useFieldArray({ control, name: "items" });

  async function onSubmit(data: CrearPlantillaForm) {
    setEnviando(true);
    const result = plantilla ? await actualizarPlantilla(plantilla.id, data) : await crearPlantilla(data);
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
      footer={
        <>
          <button type="button" className="btn btn-secondary" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="plantilla-form" className="btn btn-primary" disabled={enviando}>
            {enviando ? "Guardando..." : "Guardar"}
          </button>
        </>
      }
    >
      <form
        id="plantilla-form"
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label mb-1 block">Nombre</label>
          <input className={`input ${errors.nombre ? "input-error" : ""}`} {...register("nombre")} />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div className="border-t border-border pt-4">
          <label className="t-label mb-2 block">Tareas</label>
          <div className="flex flex-col gap-3">
            {fields.map((field, index) => (
              <div key={field.id} className="flex gap-2 rounded-md border border-border p-2">
                <div className="flex flex-1 flex-col gap-2">
                  <input
                    className="input"
                    placeholder="Título de la tarea"
                    {...register(`items.${index}.titulo` as const)}
                  />
                  <input
                    className="input"
                    placeholder="Descripción (opcional)"
                    {...register(`items.${index}.descripcion` as const)}
                  />
                </div>
                <button
                  type="button"
                  className="text-text-tertiary hover:text-error"
                  onClick={() => remove(index)}
                  disabled={fields.length === 1}
                >
                  <Trash2 size={16} />
                </button>
              </div>
            ))}
          </div>
          {errors.items && <p className="input-error-text">{errors.items.message}</p>}

          <button
            type="button"
            className="btn btn-secondary btn-sm mt-2"
            onClick={() => append({ titulo: "", descripcion: "" })}
          >
            <Plus size={14} />
            Agregar tarea
          </button>
        </div>
      </form>
    </RightPanel>
  );
}
