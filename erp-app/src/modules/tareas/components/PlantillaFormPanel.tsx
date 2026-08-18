"use client";

import { useState } from "react";
import { useForm, useFieldArray } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Plus, X } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearPlantilla } from "../actions";
import { crearPlantillaSchema, type CrearPlantillaForm } from "../types";

export function PlantillaFormPanel({ onClose }: { onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors },
  } = useForm<CrearPlantillaForm>({
    resolver: zodResolver(crearPlantillaSchema),
    defaultValues: { items: [{ titulo: "", orden: 0 }] },
  });
  const { fields, append, remove } = useFieldArray({ control, name: "items" });

  async function onSubmit(data: CrearPlantillaForm) {
    setEnviando(true);
    const result = await crearPlantilla({
      ...data,
      items: data.items.map((item, i) => ({ ...item, orden: i })),
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Plantilla creada");
    onClose();
  }

  return (
    <RightPanel
      title="Nueva plantilla"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-plantilla" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Creando…" : "Crear plantilla"}
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
          <label className="t-label mb-1 block">Nombre</label>
          <input className={`input ${errors.nombre ? "input-error" : ""}`} {...register("nombre")} />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea rows={2} className="input" {...register("descripcion")} />
        </div>

        <div>
          <label className="t-label mb-1 block">Pasos</label>
          <div className="flex flex-col gap-2">
            {fields.map((field, i) => (
              <div key={field.id} className="flex items-center gap-2">
                <input
                  className={`input ${errors.items?.[i]?.titulo ? "input-error" : ""}`}
                  {...register(`items.${i}.titulo` as const)}
                />
                <button
                  type="button"
                  className="btn btn-ghost btn-sm shrink-0"
                  onClick={() => remove(i)}
                  disabled={fields.length === 1}
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
