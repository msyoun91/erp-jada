"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { agregarTareasDesdePlantilla } from "../actions";
import { agregarDesdePlantillaSchema, type AgregarDesdePlantillaForm } from "../types";
import type { TareaPlantilla, Usuario } from "../types";
import { AsignadosPicker } from "./AsignadosPicker";

export function UsarPlantillaPanel({
  hiloId,
  plantillas,
  usuarios,
  miembros,
  usuarioActualId,
  onClose,
}: {
  hiloId: string;
  plantillas: TareaPlantilla[];
  usuarios: Usuario[];
  miembros: string[] | null;
  usuarioActualId: string | null;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors },
  } = useForm<AgregarDesdePlantillaForm>({
    resolver: zodResolver(agregarDesdePlantillaSchema),
    defaultValues: {
      hilo_id: hiloId,
      responsable_id: usuarioActualId ?? "",
      asignados: usuarioActualId ? [usuarioActualId] : [],
    },
  });

  async function onSubmit(data: AgregarDesdePlantillaForm) {
    setEnviando(true);
    const result = await agregarTareasDesdePlantilla(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tareas agregadas desde la plantilla");
    onClose();
  }

  return (
    <RightPanel
      title="Usar plantilla"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-usar-plantilla" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Agregando…" : "Agregar tareas"}
          </button>
        </>
      }
    >
      <form
        id="form-usar-plantilla"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label mb-1 block">Plantilla</label>
          <select
            className={`input ${errors.plantilla_id ? "input-error" : ""}`}
            {...register("plantilla_id")}
          >
            <option value="">— seleccionar —</option>
            {plantillas.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombre}
              </option>
            ))}
          </select>
          {errors.plantilla_id && <p className="input-error-text">{errors.plantilla_id.message}</p>}
        </div>

        <AsignadosPicker control={control} usuarios={usuarios} miembros={miembros} />
      </form>
    </RightPanel>
  );
}
