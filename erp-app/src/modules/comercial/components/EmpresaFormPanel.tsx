"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearEmpresa, editarEmpresa } from "../actions";
import { empresaSchema, type Empresa, type EmpresaForm } from "../types";
import { AvisoDuplicados } from "./AvisoDuplicados";
import { normalizar } from "./comercialLabels";

export function EmpresaFormPanel({
  empresa,
  empresas,
  onClose,
}: {
  empresa?: Empresa;
  empresas: Empresa[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<EmpresaForm>({
    resolver: zodResolver(empresaSchema),
    defaultValues: empresa
      ? {
          razon_social: empresa.razon_social,
          nombre_comercial: empresa.nombre_comercial,
          cuit: empresa.cuit,
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

  const razonSocial = useWatch({ control, name: "razon_social" }) ?? "";
  const cuit = (useWatch({ control, name: "cuit" }) ?? "").replace(/\D/g, "");
  const duplicados = empresa
    ? []
    : empresas
        .filter((e) => {
          if (cuit.length === 11 && e.cuit === cuit) return true;
          const buscado = normalizar(razonSocial);
          if (buscado.length < 3) return false;
          return (
            normalizar(e.razon_social).includes(buscado) ||
            normalizar(e.nombre_comercial ?? "").includes(buscado)
          );
        })
        .slice(0, 4)
        .map((e) => (e.cuit ? `${e.razon_social} · CUIT ${e.cuit}` : e.razon_social));

  async function onSubmit(data: EmpresaForm) {
    setEnviando(true);
    const result = empresa
      ? await editarEmpresa({ ...data, id: empresa.id })
      : await crearEmpresa(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(empresa ? "Empresa actualizada" : "Empresa creada");
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
          <button
            type="submit"
            form="form-empresa"
            className="btn btn-primary btn-sm"
            disabled={enviando}
          >
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
        <div>
          <label className="t-label t-label-req mb-1 block">Razón social</label>
          <input
            aria-required
            className={`input ${errors.razon_social ? "input-error" : ""}`}
            {...register("razon_social")}
          />
          {errors.razon_social && (
            <p className="input-error-text">{errors.razon_social.message}</p>
          )}
        </div>

        <AvisoDuplicados items={duplicados} />

        <div>
          <label className="t-label mb-1 block">Nombre comercial</label>
          <input className="input" {...register("nombre_comercial")} />
        </div>

        <div>
          <label className="t-label mb-1 block">CUIT</label>
          <input
            inputMode="numeric"
            placeholder="30712345678"
            className={`input ${errors.cuit ? "input-error" : ""}`}
            {...register("cuit")}
          />
          {errors.cuit && <p className="input-error-text">{errors.cuit.message}</p>}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Teléfono</label>
            <input className="input" {...register("telefono")} />
          </div>
          <div>
            <label className="t-label mb-1 block">Email</label>
            <input
              className={`input ${errors.email ? "input-error" : ""}`}
              {...register("email")}
            />
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
            <input className="input" {...register("provincia")} />
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
