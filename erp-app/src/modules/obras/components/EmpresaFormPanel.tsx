"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { buscarDuplicadosEmpresa, crearEmpresa, editarEmpresa } from "../actions";
import {
  crearEmpresaSchema,
  LABEL_PROVINCIA,
  PROVINCIAS,
  type CrearEmpresaForm,
  type DuplicadoEmpresa,
  type Empresa,
} from "../types";
import { AvisoDuplicadosEmpresa } from "./AvisoDuplicados";

export function EmpresaFormPanel({
  empresa,
  onClose,
  onCreada,
}: {
  empresa?: Empresa;
  onClose: () => void;
  // Alta desde una obra o desde una persona: el que abrió el panel se queda
  // con el id para armar el vínculo sin buscarla de nuevo. `pendiente` viaja
  // porque una empresa congelada todavía no se puede vincular.
  onCreada?: (id: string, pendiente: boolean, nombre: string) => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const [duplicados, setDuplicados] = useState<DuplicadoEmpresa[]>([]);

  const {
    register,
    handleSubmit,
    getValues,
    formState: { errors, isDirty },
  } = useForm<CrearEmpresaForm>({
    resolver: zodResolver(crearEmpresaSchema),
    defaultValues: empresa
      ? {
          razon_social: empresa.razon_social,
          nombre_comercial: empresa.nombre_comercial,
          website: empresa.website,
          telefono: empresa.telefono,
          email: empresa.email,
          direccion: empresa.direccion,
          localidad: empresa.localidad,
          provincia: empresa.provincia,
          observaciones: empresa.observaciones,
        }
      : {},
  });

  async function chequearDuplicados() {
    const { razon_social, nombre_comercial } = getValues();
    if (!razon_social?.trim()) return;
    setDuplicados(
      await buscarDuplicadosEmpresa(razon_social, nombre_comercial ?? undefined, empresa?.id),
    );
  }

  async function onSubmit(data: CrearEmpresaForm) {
    setEnviando(true);

    if (empresa) {
      const result = await editarEmpresa({ ...data, id: empresa.id });
      setEnviando(false);
      if (!result.success) {
        toast.error(result.error);
        return;
      }
      toast.success("Empresa actualizada");
    } else {
      const result = await crearEmpresa(data);
      setEnviando(false);
      if (!result.success) {
        toast.error(result.error);
        return;
      }
      if (result.pendiente) {
        toast.warning(
          "Empresa creada, pendiente de autorización: se parece a una que ya existe. No se puede vincular hasta que la aprueben.",
        );
      } else {
        toast.success("Empresa creada");
      }
      onCreada?.(result.id, result.pendiente, data.razon_social);
    }

    onClose();
  }

  return (
    <RightPanel
      title={empresa ? "Modificar empresa" : "Nueva empresa"}
      subtitle={empresa?.razon_social}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-empresa" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : empresa ? "Guardar cambios" : "Crear empresa"}
          </button>
        </>
      }
    >
      <form
        id="form-empresa"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        {duplicados.length > 0 && (
          <AvisoDuplicadosEmpresa
            duplicados={duplicados}
            onUsar={onCreada ? (id, nombre) => { onCreada(id, false, nombre); onClose(); } : undefined}
          />
        )}

        <div>
          <label className="t-label t-label-req mb-1 block">Razón social</label>
          <input
            className={`input ${errors.razon_social ? "input-error" : ""}`}
            {...register("razon_social", { onBlur: chequearDuplicados })}
          />
          {errors.razon_social && <p className="input-error-text">{errors.razon_social.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Nombre comercial</label>
          <input className="input" {...register("nombre_comercial", { onBlur: chequearDuplicados })} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Teléfono</label>
            <input className="input" {...register("telefono")} />
          </div>
          <div>
            <label className="t-label mb-1 block">Email</label>
            <input className={`input ${errors.email ? "input-error" : ""}`} {...register("email")} />
            {errors.email && <p className="input-error-text">{errors.email.message}</p>}
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Website</label>
          <input className="input" {...register("website")} />
        </div>

        <div>
          <label className="t-label mb-1 block">Dirección</label>
          <input className="input" {...register("direccion")} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Localidad</label>
            <input className="input" {...register("localidad")} />
          </div>
          <div>
            <label className="t-label mb-1 block">Provincia</label>
            <select className="input" {...register("provincia")}>
              <option value="">Sin especificar</option>
              {PROVINCIAS.map((p) => (
                <option key={p} value={p}>
                  {LABEL_PROVINCIA[p]}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
