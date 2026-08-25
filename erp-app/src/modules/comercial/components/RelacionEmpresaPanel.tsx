"use client";

import { useState } from "react";
import { useController, useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { guardarRelacionEmpresa } from "../actions";
import {
  ROLES_EMPRESA,
  relacionEmpresaSchema,
  type Empresa,
  type EmpresaConRoles,
  type RelacionEmpresaForm,
  type RolEmpresa,
} from "../types";
import { ROL_EMPRESA_LABEL } from "./comercialLabels";
import { RolesPicker } from "./RolesPicker";

export function RelacionEmpresaPanel({
  obraId,
  relacion,
  empresas,
  yaRelacionadas,
  onClose,
}: {
  obraId: string;
  relacion?: EmpresaConRoles;
  empresas: Empresa[];
  yaRelacionadas: string[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<RelacionEmpresaForm>({
    resolver: zodResolver(relacionEmpresaSchema),
    defaultValues: relacion
      ? {
          obra_id: obraId,
          empresa_id: relacion.empresa_id,
          roles: relacion.roles,
          observaciones: relacion.observaciones,
        }
      : { obra_id: obraId, roles: [] },
  });

  const rolesField = useController({ name: "roles", control });

  // Una empresa entra una sola vez por obra: sus varios roles van en la misma
  // fila. Ofrecerla de nuevo sería chocar contra el unique parcial.
  const disponibles = empresas.filter(
    (e) => e.id === relacion?.empresa_id || !yaRelacionadas.includes(e.id)
  );

  async function onSubmit(data: RelacionEmpresaForm) {
    setEnviando(true);
    const result = await guardarRelacionEmpresa(
      relacion ? { ...data, id: relacion.id } : data
    );
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(relacion ? "Relación actualizada" : "Empresa agregada a la obra");
    onClose();
  }

  return (
    <RightPanel
      title={relacion ? "Modificar empresa de la obra" : "Agregar empresa a la obra"}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="submit"
            form="form-relacion-empresa"
            className="btn btn-primary btn-sm"
            disabled={enviando}
          >
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <form
        id="form-relacion-empresa"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Empresa</label>
          <select
            className={`input ${errors.empresa_id ? "input-error" : ""}`}
            disabled={Boolean(relacion)}
            {...register("empresa_id")}
          >
            <option value="">Elegí una empresa</option>
            {disponibles.map((e) => (
              <option key={e.id} value={e.id}>
                {e.razon_social}
              </option>
            ))}
          </select>
          {errors.empresa_id && <p className="input-error-text">{errors.empresa_id.message}</p>}
        </div>

        <RolesPicker<RolEmpresa>
          opciones={ROLES_EMPRESA}
          labels={ROL_EMPRESA_LABEL}
          value={(rolesField.field.value ?? []) as RolEmpresa[]}
          onChange={rolesField.field.onChange}
          error={errors.roles?.message}
        />

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
