"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import type { UsuarioBasico } from "@/lib/usuarios";
import { cambiarEstado, sumarParticipante, transferirObra } from "../actions";
import { MOTIVO } from "../etiquetas";
import {
  ESTADOS_ABIERTOS,
  LABEL_ESTADO,
  estadoSchema,
  participanteSchema,
  transferirSchema,
  type EstadoForm,
  type EstadoObra,
  type Obra,
  type ParticipanteForm,
  type TransferirForm,
} from "../types";

// A dónde se puede ir desde cada estado (OB008, OB010); la base lo hace valer.
// Con Presupuestos, `contratada` la pondrá solo la base.
function destinos(desde: EstadoObra): EstadoObra[] {
  const abiertos = ESTADOS_ABIERTOS.filter((e) => e !== desde);
  if (desde === "contratada" || desde === "perdida") return [...ESTADOS_ABIERTOS];
  return [...abiertos, "contratada", "perdida"];
}

export function EstadoModal({ obra, inicial, onClose }: { obra: Obra; inicial: EstadoObra | null; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const opciones = destinos(obra.estado);
  const { register, handleSubmit, control, formState } = useForm<EstadoForm>({
    resolver: zodResolver(estadoSchema),
    defaultValues: {
      id: obra.id,
      anterior: obra.estado,
      estado: inicial && opciones.includes(inicial) ? inicial : opciones[0],
      motivo_perdida: "",
      estado_nota: "",
    },
  });
  const { errors } = formState;
  const estado = useWatch({ control, name: "estado" });
  const motivo = useWatch({ control, name: "motivo_perdida" });
  const revierte = obra.estado === "contratada";
  const ejemplo = motivo ? MOTIVO[motivo as keyof typeof MOTIVO]?.ejemplo : undefined;

  async function onSubmit(data: EstadoForm) {
    setEnviando(true);
    const result = await cambiarEstado(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(`Pasó a ${LABEL_ESTADO[data.estado].label}`);
    onClose();
  }

  return (
    <FormModal title="Cambiar estado" confirmLabel="Cambiar" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      <p className="t-body-m">
        Hoy está en <span className="font-semibold">{LABEL_ESTADO[obra.estado].label}</span>.
      </p>
      <Campo id="estado-nuevo" label="Pasa a" requerido error={errors.estado}>
        <select id="estado-nuevo" aria-required className={claseInput(errors.estado)} {...register("estado")}>
          {opciones.map((e) => (
            <option key={e} value={e}>
              {LABEL_ESTADO[e].label}
            </option>
          ))}
        </select>
      </Campo>
      {estado === "perdida" && (
        <Campo id="estado-motivo" label="Motivo" requerido error={errors.motivo_perdida}>
          <select id="estado-motivo" aria-required className={claseInput(errors.motivo_perdida)} {...register("motivo_perdida")}>
            <option value="">¿Por qué se perdió?</option>
            {Object.entries(MOTIVO).map(([valor, m]) => (
              <option key={valor} value={valor}>
                {m.label}
              </option>
            ))}
          </select>
        </Campo>
      )}
      {(estado === "perdida" || revierte) && (
        <Campo
          id="estado-nota"
          label={revierte ? "Por qué vuelve atrás" : "Detalle"}
          requerido={revierte || motivo === "otro"}
          error={errors.estado_nota}
        >
          <textarea
            id="estado-nota"
            rows={3}
            placeholder={revierte ? "El cliente pidió recotizar" : ejemplo}
            className={claseInput(errors.estado_nota)}
            {...register("estado_nota")}
          />
        </Campo>
      )}
    </FormModal>
  );
}

export function TransferirModal({
  obra,
  candidatos,
  onClose,
}: {
  obra: Obra;
  candidatos: UsuarioBasico[];
  onClose: () => void;
}) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<TransferirForm>({
    resolver: zodResolver(transferirSchema),
    defaultValues: { id: obra.id, responsable_id: "", quedarme: false },
  });

  async function onSubmit(data: TransferirForm) {
    setEnviando(true);
    const result = await transferirObra(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Obra transferida");
    // Sin quedarse, quien transfiere puede dejar de verla.
    if (!data.quedarme) router.push("/obras");
    onClose();
  }

  return (
    <FormModal title="Transferir obra" confirmLabel="Transferir" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      <Campo id="transferir-a" label="Nuevo responsable" requerido error={formState.errors.responsable_id}>
        <select id="transferir-a" aria-required className={claseInput(formState.errors.responsable_id)} {...register("responsable_id")}>
          <option value="">Elegí a quién</option>
          {candidatos
            .filter((c) => c.id !== obra.responsable_id)
            .map((c) => (
              <option key={c.id} value={c.id}>
                {c.nombre}
              </option>
            ))}
        </select>
      </Campo>
      <label className="t-body-m flex items-center gap-2">
        <input type="checkbox" {...register("quedarme")} />
        Seguir como participante
      </label>
    </FormModal>
  );
}

export function SumarParticipanteModal({
  obraId,
  candidatos,
  onClose,
}: {
  obraId: string;
  candidatos: UsuarioBasico[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<ParticipanteForm>({
    resolver: zodResolver(participanteSchema),
    defaultValues: { obra_id: obraId, usuario_id: "" },
  });

  async function onSubmit(data: ParticipanteForm) {
    setEnviando(true);
    const result = await sumarParticipante(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Participante sumado");
    onClose();
  }

  return (
    <FormModal title="Sumar participante" confirmLabel="Sumar" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      <p className="t-body-m">Ve y trabaja la obra: la edita, le cambia el estado y le vincula contactos.</p>
      <Campo id="participante" label="Quién" requerido error={formState.errors.usuario_id}>
        <select id="participante" aria-required className={claseInput(formState.errors.usuario_id)} {...register("usuario_id")}>
          <option value="">Elegí a quién</option>
          {candidatos.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre}
            </option>
          ))}
        </select>
      </Campo>
    </FormModal>
  );
}
