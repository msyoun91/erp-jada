"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { agregarTareasDesdePlantilla } from "../actions";
import { agregarDesdePlantillaSchema, type AgregarDesdePlantillaForm } from "../types";
import type { TareaPlantilla } from "../types";
import { AsignadosPicker } from "./AsignadosPicker";
import { useTareasContexto } from "./tareasContexto";

export function UsarPlantillaPanel({
  hiloId,
  plantillas,
  miembros,
  onClose,
}: {
  hiloId: string;
  plantillas: TareaPlantilla[];
  miembros: string[] | null;
  onClose: () => void;
}) {
  const { usuarioActualId } = useTareasContexto();
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
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
    toast.success("Pasos agregados desde la plantilla");
    onClose();
  }

  return (
    <RightPanel
      title="Usar plantilla"
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-usar-plantilla" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Agregando…" : "Agregar pasos"}
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
          <label className="t-label t-label-req mb-1 block">Plantilla</label>
          <select
            aria-required
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
          <p className="t-caption mt-2">
            Los pasos se crean encadenados: cada uno se habilita al completar el anterior.
          </p>
        </div>

        <AsignadosPicker
          control={control}
          miembros={miembros}
        />
      </form>
    </RightPanel>
  );
}
