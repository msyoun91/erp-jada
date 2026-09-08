"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { buscarDuplicadosPersona, crearPersona, editarPersona } from "../actions";
import { crearPersonaSchema, type CrearPersonaForm, type DuplicadoPersona } from "../types";
import { AvisoDuplicadosPersona } from "./AvisoDuplicados";

// `persona` no es la fila cruda de la tabla: los datos de contacto salen por
// obras_ficha_persona(), que deja registro. Por eso el panel de edición recibe
// lo que devolvió esa función y no un select directo.
export type PersonaEditable = {
  id: string;
  nombre: string;
  apellido: string | null;
  telefono: string | null;
  whatsapp: string | null;
  email: string | null;
  observaciones: string | null;
};

export function PersonaFormPanel({
  persona,
  onClose,
  onCreada,
}: {
  persona?: PersonaEditable;
  onClose: () => void;
  // `pendiente` viaja porque una persona congelada todavía no se puede
  // vincular a ninguna obra.
  onCreada?: (id: string, pendiente: boolean, nombre: string) => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const [duplicados, setDuplicados] = useState<DuplicadoPersona[]>([]);

  const {
    register,
    handleSubmit,
    getValues,
    formState: { errors, isDirty },
  } = useForm<CrearPersonaForm>({
    resolver: zodResolver(crearPersonaSchema),
    defaultValues: persona
      ? {
          nombre: persona.nombre,
          apellido: persona.apellido,
          telefono: persona.telefono,
          whatsapp: persona.whatsapp,
          email: persona.email,
          observaciones: persona.observaciones,
        }
      : {},
  });

  async function chequearDuplicados() {
    const { nombre, apellido, email, telefono } = getValues();
    if (!nombre?.trim()) return;
    setDuplicados(
      await buscarDuplicadosPersona(
        nombre,
        apellido ?? undefined,
        email ?? undefined,
        telefono ?? undefined,
        persona?.id,
      ),
    );
  }

  async function onSubmit(data: CrearPersonaForm) {
    setEnviando(true);

    if (persona) {
      const result = await editarPersona({ ...data, id: persona.id });
      setEnviando(false);
      if (!result.success) {
        toast.error(result.error);
        return;
      }
      toast.success("Persona actualizada");
    } else {
      const result = await crearPersona(data);
      setEnviando(false);
      if (!result.success) {
        toast.error(result.error);
        return;
      }
      if (result.pendiente) {
        toast.warning(
          "Persona creada, pendiente de autorización: se parece a una que ya existe. No se puede vincular hasta que la aprueben.",
        );
      } else {
        toast.success("Persona creada");
      }
      onCreada?.(result.id, result.pendiente, [data.nombre, data.apellido].filter(Boolean).join(" "));
    }

    onClose();
  }

  return (
    <RightPanel
      title={persona ? "Modificar persona" : "Nueva persona"}
      subtitle={persona && `${persona.nombre} ${persona.apellido ?? ""}`.trim()}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-persona" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : persona ? "Guardar cambios" : "Crear persona"}
          </button>
        </>
      }
    >
      <form
        id="form-persona"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        {duplicados.length > 0 && (
          <AvisoDuplicadosPersona
            duplicados={duplicados}
            onUsar={onCreada ? (id, nombre) => { onCreada(id, false, nombre); onClose(); } : undefined}
          />
        )}

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label className="t-label t-label-req mb-1 block">Nombre</label>
            <input
              className={`input ${errors.nombre ? "input-error" : ""}`}
              {...register("nombre", { onBlur: chequearDuplicados })}
            />
            {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
          </div>
          <div>
            <label className="t-label mb-1 block">Apellido</label>
            <input className="input" {...register("apellido", { onBlur: chequearDuplicados })} />
          </div>
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label className="t-label mb-1 block">Teléfono</label>
            <input className="input" {...register("telefono", { onBlur: chequearDuplicados })} />
          </div>
          <div>
            <label className="t-label mb-1 block">WhatsApp</label>
            <input className="input" {...register("whatsapp")} />
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Email</label>
          <input
            className={`input ${errors.email ? "input-error" : ""}`}
            {...register("email", { onBlur: chequearDuplicados })}
          />
          {errors.email && <p className="input-error-text">{errors.email.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
