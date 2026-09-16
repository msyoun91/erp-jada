"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { useConfirmarAcceso } from "@/components/ui/CompartirAccesoPanel";
import { reasignarTarea, sinAccesoTarea } from "../actions";
import { reasignarTareaSchema, type ReasignarTareaForm } from "../types";
import { AsignadosPicker } from "./AsignadosPicker";
import { useTareasContexto } from "./tareasContexto";

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
  const { usuarioActualId } = useTareasContexto();
  const [enviando, setEnviando] = useState(false);
  const { confirmarAcceso, panelAcceso } = useConfirmarAcceso({ verbo: "guardar", puedeDejarAfuera: true });
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

  async function guardar(data: ReasignarTareaForm, aviso: string | null) {
    setEnviando(true);
    const result = await reasignarTarea(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    if (aviso) toast.warning(aviso);
    toast.success("Tarea reasignada");
    onClose();
  }

  async function onSubmit(data: ReasignarTareaForm) {
    const asignadosDestino = data.asignados.filter((id) => id !== usuarioActualId);

    if (asignadosDestino.length === 0) {
      await guardar(data, null);
      return;
    }

    setEnviando(true);
    const result = await sinAccesoTarea({ tarea_id: tareaId, usuarios: asignadosDestino });
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    await confirmarAcceso(result.filas, (aviso) => guardar(data, aviso));
  }

  return (
    <>
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
    {panelAcceso}
    </>
  );
}
