"use client";

import { useState } from "react";
import { useController, useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarRelacionPersona } from "../actions";
import {
  ROLES_PERSONA,
  relacionPersonaSchema,
  type Empresa,
  type PersonaConEmpresa,
  type PersonaConRoles,
  type RelacionPersonaForm,
  type RolPersona,
} from "../types";
import { nombrePersona, ROL_PERSONA_LABEL } from "./comercialLabels";
import { RolesPicker } from "./RolesPicker";

export function RelacionPersonaPanel({
  obraId,
  relacion,
  personas,
  empresas,
  yaRelacionadas,
  hayOtroReferente,
  verComision,
  onClose,
}: {
  obraId: string;
  relacion?: PersonaConRoles;
  personas: PersonaConEmpresa[];
  empresas: Empresa[];
  yaRelacionadas: string[];
  hayOtroReferente: boolean;
  verComision: boolean;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const comisionActual = relacion?.comercial_comisiones.find((c) => c.activo)?.porcentaje ?? null;

  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<RelacionPersonaForm>({
    resolver: zodResolver(relacionPersonaSchema),
    defaultValues: relacion
      ? {
          obra_id: obraId,
          persona_id: relacion.persona_id,
          empresa_id: relacion.empresa_id ?? "",
          roles: relacion.roles,
          es_referente: relacion.es_referente,
          porcentaje_comision: comisionActual ?? "",
          observaciones: relacion.observaciones,
        }
      : { obra_id: obraId, roles: [], es_referente: false, porcentaje_comision: "" },
  });

  const rolesField = useController({ name: "roles", control });
  const esReferente = useWatch({ control, name: "es_referente" });

  const disponibles = personas.filter(
    (p) => p.id === relacion?.persona_id || !yaRelacionadas.includes(p.id)
  );

  async function onSubmit(data: RelacionPersonaForm) {
    setEnviando(true);
    const result = await guardarRelacionPersona(
      relacion ? { ...data, id: relacion.id } : data
    );
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(relacion ? "Relación actualizada" : "Persona agregada a la obra");
    onClose();
  }

  return (
    <RightPanel
      title={relacion ? "Modificar persona de la obra" : "Agregar persona a la obra"}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="submit"
            form="form-relacion-persona"
            className="btn btn-primary btn-sm"
            disabled={enviando}
          >
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <form
        id="form-relacion-persona"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Persona</label>
          <select
            className={`input ${errors.persona_id ? "input-error" : ""}`}
            disabled={Boolean(relacion)}
            {...register("persona_id")}
          >
            <option value="">Elegí una persona</option>
            {disponibles.map((p) => (
              <option key={p.id} value={p.id}>
                {nombrePersona(p)}
              </option>
            ))}
          </select>
          {errors.persona_id && <p className="input-error-text">{errors.persona_id.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Empresa en esta obra</label>
          <select className="input" {...register("empresa_id")}>
            <option value="">Sin empresa</option>
            {empresas.map((e) => (
              <option key={e.id} value={e.id}>
                {e.razon_social}
              </option>
            ))}
          </select>
          <p className="t-caption mt-1">
            Puede no ser su empresa principal — en esta obra participa por esta.
          </p>
        </div>

        <RolesPicker<RolPersona>
          opciones={ROLES_PERSONA}
          labels={ROL_PERSONA_LABEL}
          value={(rolesField.field.value ?? []) as RolPersona[]}
          onChange={rolesField.field.onChange}
          error={errors.roles?.message}
        />

        <div>
          <label className="tap-target flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              disabled={hayOtroReferente}
              className="h-4 w-4 shrink-0 accent-brand-700"
              {...register("es_referente")}
            />
            <span className="t-body-m">Es el referente de la obra</span>
          </label>
          <p className="t-caption mt-1">
            {hayOtroReferente
              ? "Esta obra ya tiene referente. Sacale la marca al otro antes de ponerla acá."
              : "Quien originó, facilitó o derivó la oportunidad. No es lo mismo que decisor."}
          </p>
        </div>

        {verComision && esReferente && (
          <div>
            <label className="t-label mb-1 block">Comisión (%)</label>
            <input
              type="number"
              step="0.01"
              min={0}
              max={100}
              placeholder="Vacío = sin comisión"
              className={`input ${errors.porcentaje_comision ? "input-error" : ""}`}
              {...register("porcentaje_comision")}
            />
            {errors.porcentaje_comision && (
              <p className="input-error-text">{errors.porcentaje_comision.message}</p>
            )}
            <p className="t-caption mt-1">
              Vacío no es lo mismo que 0: vacío es sin comisión, 0 es una comisión del 0%.
            </p>
          </div>
        )}

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
