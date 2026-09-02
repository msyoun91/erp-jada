"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { reasignarTarea } from "../actions";
import { reasignarTareaSchema, type ReasignarTareaForm } from "../types";
import { AsignadosPicker } from "./AsignadosPicker";

export function ReasignarPanel({
  tareaId,
  asignadosActuales,
  responsableActual,
  miembros,
  onClose,
}: {
  tareaId: string;
  asignadosActuales: string[];
  responsableActual: string;
  miembros: string[] | null;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    handleSubmit,
    control,
    formState: { isDirty },
  } = useForm<ReasignarTareaForm>({
    resolver: zodResolver(reasignarTareaSchema),
    defaultValues: {
      tarea_id: tareaId,
      asignados: asignadosActuales,
      responsable_id: responsableActual,
    },
  });

  async function onSubmit(data: ReasignarTareaForm) {
    setEnviando(true);
    const result = await reasignarTarea(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea reasignada");
    onClose();
  }

  return (
    <RightPanel
      title="Reasignar tarea"
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-reasignar" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <form
        id="form-reasignar"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        {/* El panel entero es la función `tareas_asignar`: quien no la tiene
            no llega acá (TareaDetailPanel no ofrece "Reasignar"). */}
        <AsignadosPicker control={control} miembros={miembros} />
      </form>
    </RightPanel>
  );
}
