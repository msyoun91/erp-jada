"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearPersona, editarPersona } from "../actions";
import {
  personaSchema,
  type Empresa,
  type PersonaConEmpresa,
  type PersonaForm,
} from "../types";
import { AvisoDuplicados } from "./AvisoDuplicados";
import { nombrePersona, normalizar } from "./comercialLabels";

export function PersonaFormPanel({
  persona,
  personas,
  empresas,
  onClose,
}: {
  persona?: PersonaConEmpresa;
  personas: PersonaConEmpresa[];
  empresas: Empresa[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<PersonaForm>({
    resolver: zodResolver(personaSchema),
    defaultValues: persona
      ? {
          nombre: persona.nombre,
          apellido: persona.apellido,
          telefono: persona.telefono,
          whatsapp: persona.whatsapp,
          email: persona.email,
          cargo: persona.cargo,
          empresa_principal_id: persona.empresa_principal_id ?? "",
          observaciones: persona.observaciones,
        }
      : {},
  });

  const nombre = normalizar(
    `${useWatch({ control, name: "nombre" }) ?? ""} ${useWatch({ control, name: "apellido" }) ?? ""}`
  );
  const email = normalizar(useWatch({ control, name: "email" }) ?? "");
  const duplicados = persona
    ? []
    : personas
        .filter((p) => {
          if (email.length > 3 && normalizar(p.email ?? "") === email) return true;
          if (nombre.length < 4) return false;
          return normalizar(nombrePersona(p)).includes(nombre);
        })
        .slice(0, 4)
        .map((p) =>
          [nombrePersona(p), p.empresas?.razon_social, p.email].filter(Boolean).join(" · ")
        );

  async function onSubmit(data: PersonaForm) {
    setEnviando(true);
    const result = persona
      ? await editarPersona({ ...data, id: persona.id })
      : await crearPersona(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(persona ? "Persona actualizada" : "Persona creada");
    onClose();
  }

  return (
    <RightPanel
      title={persona ? "Modificar persona" : "Nueva persona"}
      subtitle={persona ? nombrePersona(persona) : undefined}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="submit"
            form="form-persona"
            className="btn btn-primary btn-sm"
            disabled={enviando}
          >
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
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label t-label-req mb-1 block">Nombre</label>
            <input
              aria-required
              className={`input ${errors.nombre ? "input-error" : ""}`}
              {...register("nombre")}
            />
            {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
          </div>
          <div>
            <label className="t-label mb-1 block">Apellido</label>
            <input className="input" {...register("apellido")} />
          </div>
        </div>

        <AvisoDuplicados items={duplicados} />

        <div>
          <label className="t-label mb-1 block">Empresa principal</label>
          <select className="input" {...register("empresa_principal_id")}>
            <option value="">Sin empresa</option>
            {empresas.map((e) => (
              <option key={e.id} value={e.id}>
                {e.razon_social}
              </option>
            ))}
          </select>
          <p className="t-caption mt-1">
            Con qué empresa participa en cada obra se define en la obra, no acá.
          </p>
        </div>

        <div>
          <label className="t-label mb-1 block">Cargo</label>
          <input className="input" {...register("cargo")} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Teléfono</label>
            <input className="input" {...register("telefono")} />
          </div>
          <div>
            <label className="t-label mb-1 block">WhatsApp</label>
            <input className="input" {...register("whatsapp")} />
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Email</label>
          <input className={`input ${errors.email ? "input-error" : ""}`} {...register("email")} />
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
