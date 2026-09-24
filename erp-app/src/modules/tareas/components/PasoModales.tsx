"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { completarPaso, completarPasoAjeno, ponerEnEspera, reasignarPaso, rechazarPaso } from "../actions";
import {
  completarAjenoSchema,
  completarSchema,
  esperaSchema,
  reasignarSchema,
  rechazarSchema,
  type CompletarAjenoForm,
  type CompletarForm,
  type EsperaForm,
  type ReasignarForm,
  type RechazarForm,
  type Tarea,
} from "../types";
import { AsignadoSelect } from "./AsignadoSelect";
import { Campo, claseInput } from "./Campo";
import { FormModal } from "./FormModal";

type Props = { paso: Tarea; onClose: () => void };

function useEnvio<T>(accion: (d: T) => Promise<{ success: boolean; error?: string }>, ok: string, onClose: () => void) {
  const [enviando, setEnviando] = useState(false);
  async function enviar(data: T) {
    setEnviando(true);
    const result = await accion(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(ok);
    onClose();
  }
  return { enviando, enviar };
}

// Rechazar un pedido y devolver uno aceptado son el mismo gesto: motivo obligatorio.
export function RechazarModal({ paso, onClose, devolver }: Props & { devolver: boolean }) {
  const { enviando, enviar } = useEnvio(rechazarPaso, devolver ? "Pedido devuelto" : "Pedido rechazado", onClose);
  const { register, handleSubmit, formState } = useForm<RechazarForm>({
    resolver: zodResolver(rechazarSchema),
    defaultValues: { id: paso.id, motivo_rechazo: "" },
  });
  const error = formState.errors.motivo_rechazo;
  return (
    <FormModal
      title={devolver ? "Devolver pedido" : "Rechazar pedido"}
      confirmLabel={devolver ? "Devolver" : "Rechazar"}
      peligro
      onClose={onClose}
      onSubmit={handleSubmit(enviar)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      <Campo id="rechazo-motivo" label="Motivo" requerido error={error}>
        <textarea id="rechazo-motivo" rows={3} aria-required className={claseInput(error)} {...register("motivo_rechazo")} />
      </Campo>
    </FormModal>
  );
}

export function CompletarModal({ paso, onClose }: Props) {
  const { enviando, enviar } = useEnvio(completarPaso, "Paso completado", onClose);
  const { register, handleSubmit, formState } = useForm<CompletarForm>({
    resolver: zodResolver(completarSchema),
    defaultValues: { id: paso.id, resultado: "" },
  });
  const error = formState.errors.resultado;
  return (
    <FormModal title="Completar paso" confirmLabel="Completar" onClose={onClose} onSubmit={handleSubmit(enviar)} enviando={enviando}>
      <Campo id="completar-resultado" label="Resultado" error={error}>
        <textarea id="completar-resultado" rows={3} placeholder="Opcional" className={claseInput(error)} {...register("resultado")} />
      </Campo>
    </FormModal>
  );
}

// El admin completa lo ajeno con una nota suya, en la misma transacción (TA012).
export function CompletarAjenoModal({ paso, onClose }: Props) {
  const { enviando, enviar } = useEnvio(completarPasoAjeno, "Paso completado", onClose);
  const { register, handleSubmit, formState } = useForm<CompletarAjenoForm>({
    resolver: zodResolver(completarAjenoSchema),
    defaultValues: { id: paso.id, nota: "", resultado: "" },
  });
  const { errors } = formState;
  return (
    <FormModal
      title="Completar paso ajeno"
      confirmLabel="Completar"
      onClose={onClose}
      onSubmit={handleSubmit(enviar)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      <Campo id="ajeno-nota" label="Nota" requerido error={errors.nota}>
        <textarea id="ajeno-nota" rows={3} aria-required placeholder="Por qué lo completás vos" className={claseInput(errors.nota)} {...register("nota")} />
      </Campo>
      <Campo id="ajeno-resultado" label="Resultado" error={errors.resultado}>
        <textarea id="ajeno-resultado" rows={2} placeholder="Opcional" className={claseInput(errors.resultado)} {...register("resultado")} />
      </Campo>
    </FormModal>
  );
}

// Sin fecha, sale de la espera.
export function EsperaModal({ paso, onClose }: Props) {
  const { enviando, enviar } = useEnvio(ponerEnEspera, paso.espera_hasta ? "Espera actualizada" : "Paso en espera", onClose);
  const { register, handleSubmit, formState } = useForm<EsperaForm>({
    resolver: zodResolver(esperaSchema),
    defaultValues: { id: paso.id, espera_hasta: paso.espera_hasta ?? "", espera_motivo: paso.espera_motivo ?? "" },
  });
  const { errors } = formState;
  return (
    <FormModal title="Poner en espera" confirmLabel="Guardar" onClose={onClose} onSubmit={handleSubmit(enviar)} enviando={enviando}>
      <Campo id="espera-hasta" label="Hasta" error={errors.espera_hasta}>
        <input id="espera-hasta" type="date" className={claseInput(errors.espera_hasta)} {...register("espera_hasta")} />
      </Campo>
      <Campo id="espera-motivo" label="Motivo" error={errors.espera_motivo}>
        <input id="espera-motivo" className={claseInput(errors.espera_motivo)} {...register("espera_motivo")} />
      </Campo>
    </FormModal>
  );
}

export function ReasignarModal({ paso, onClose, soloMiEquipo }: Props & { soloMiEquipo: boolean }) {
  const { enviando, enviar } = useEnvio(reasignarPaso, "Paso reasignado", onClose);
  const { handleSubmit, control, setValue, formState } = useForm<ReasignarForm>({
    resolver: zodResolver(reasignarSchema),
    defaultValues: { id: paso.id, asignado_id: paso.asignado_id, asignado_equipo_id: paso.asignado_equipo_id },
  });
  const [asignadoId, asignadoEquipoId] = useWatch({ control, name: ["asignado_id", "asignado_equipo_id"] });
  return (
    <FormModal title="Reasignar paso" confirmLabel="Reasignar" onClose={onClose} onSubmit={handleSubmit(enviar)} enviando={enviando}>
      <Campo id="reasignar-a" label="A quién" requerido error={formState.errors.asignado_id}>
        <AsignadoSelect
          id="reasignar-a"
          soloMiEquipo={soloMiEquipo}
          invalido={!!formState.errors.asignado_id}
          value={{ asignado_id: asignadoId ?? null, asignado_equipo_id: asignadoEquipoId ?? null }}
          onChange={(v) => {
            setValue("asignado_id", v.asignado_id, { shouldDirty: true });
            setValue("asignado_equipo_id", v.asignado_equipo_id, { shouldDirty: true });
          }}
        />
      </Campo>
    </FormModal>
  );
}
