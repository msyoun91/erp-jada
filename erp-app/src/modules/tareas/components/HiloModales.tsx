"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { cerrarHilo, transferirHilo } from "../actions";
import { cerrarHiloSchema, transferirSchema, type CerrarHiloForm, type Hilo, type TransferirForm } from "../types";
import { Campo, claseInput } from "./Campo";
import { useTareas } from "./contexto";
import { FormModal } from "./FormModal";

// Con pasos abiertos no se cierra (TA008): cerrar los cancela.
export function CerrarHiloModal({ hilo, abiertos, onClose }: { hilo: Hilo; abiertos: number; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const recurrente = hilo.recurrencia_unidad !== null;
  const { register, handleSubmit, formState } = useForm<CerrarHiloForm>({
    resolver: zodResolver(cerrarHiloSchema),
    defaultValues: { id: hilo.id, resultado: "", generar: true, cancelar_pendientes: abiertos > 0 },
  });

  async function onSubmit(data: CerrarHiloForm) {
    setEnviando(true);
    const result = await cerrarHilo(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo cerrado");
    onClose();
  }

  return (
    <FormModal title="Cerrar hilo" confirmLabel="Cerrar hilo" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      {abiertos > 0 && (
        <p className="t-body-m">
          {abiertos === 1 ? "Queda 1 paso abierto: se cancela" : `Quedan ${abiertos} pasos abiertos: se cancelan`} al
          cerrar.
        </p>
      )}
      <Campo id="cerrar-resultado" label="Resultado" error={formState.errors.resultado}>
        <textarea id="cerrar-resultado" rows={3} placeholder="Opcional" className={claseInput(formState.errors.resultado)} {...register("resultado")} />
      </Campo>
      {recurrente && (
        <label className="t-body-m flex items-center gap-2">
          <input type="checkbox" {...register("generar")} />
          Crear el siguiente
        </label>
      )}
    </FormModal>
  );
}

// Afuera del equipo del hilo: solo al delegador del equipo destino, con
// tareas_pedir (TA010, TA015). La base lo explica si no se puede.
export function TransferirModal({ hilo, onClose }: { hilo: Hilo; onClose: () => void }) {
  const { asignables, yo } = useTareas();
  const [enviando, setEnviando] = useState(false);
  const personas = asignables.filter((a) => a.usuario_id && a.puede_recibir && a.usuario_id !== hilo.responsable_id);
  const { register, handleSubmit, formState } = useForm<TransferirForm>({
    resolver: zodResolver(transferirSchema),
    defaultValues: { id: hilo.id, responsable_id: "" },
  });

  async function onSubmit(data: TransferirForm) {
    setEnviando(true);
    const result = await transferirHilo(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo transferido");
    onClose();
  }

  return (
    <FormModal title="Transferir hilo" confirmLabel="Transferir" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      <Campo id="transferir-a" label="Nuevo responsable" requerido error={formState.errors.responsable_id}>
        <select id="transferir-a" aria-required className={claseInput(formState.errors.responsable_id)} {...register("responsable_id")}>
          <option value="">Elegí a quién</option>
          {personas.map((a) => (
            <option key={a.usuario_id} value={a.usuario_id}>
              {a.usuario_id === yo ? `${a.nombre} (yo)` : a.nombre}
            </option>
          ))}
        </select>
      </Campo>
    </FormModal>
  );
}
