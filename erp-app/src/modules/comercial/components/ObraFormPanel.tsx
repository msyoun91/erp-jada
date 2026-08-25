"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearObra, editarObra } from "../actions";
import {
  ESTADOS_OBRA,
  TIPOS_OBRA,
  obraSchema,
  type Obra,
  type ObraForm,
} from "../types";
import { AvisoDuplicados } from "./AvisoDuplicados";
import { ESTADO_OBRA_LABEL, TIPO_OBRA_LABEL, normalizar } from "./comercialLabels";

export function ObraFormPanel({
  obra,
  obras,
  onClose,
}: {
  obra?: Obra;
  obras: Obra[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<ObraForm>({
    resolver: zodResolver(obraSchema),
    defaultValues: obra
      ? {
          nombre: obra.nombre,
          direccion: obra.direccion,
          localidad: obra.localidad,
          provincia: obra.provincia,
          tipo: obra.tipo,
          estado_obra: obra.estado_obra,
          cantidad_unidades: obra.cantidad_unidades ?? "",
          superficie_estimada: obra.superficie_estimada ?? "",
          fecha_estimada_inicio: obra.fecha_estimada_inicio,
          observaciones: obra.observaciones,
        }
      : { tipo: "otro", estado_obra: "desconocido" },
  });

  // El nombre de una obra no es único: "Edificio Belgrano" puede existir en
  // dos localidades. Se avisa comparando nombre y, si está cargada, dirección.
  const nombre = normalizar(useWatch({ control, name: "nombre" }) ?? "");
  const duplicados =
    obra || nombre.length < 3
      ? []
      : obras
          .filter((o) => normalizar(o.nombre).includes(nombre))
          .slice(0, 4)
          .map((o) => [o.nombre, o.direccion, o.localidad].filter(Boolean).join(" · "));

  async function onSubmit(data: ObraForm) {
    setEnviando(true);
    const result = obra ? await editarObra({ ...data, id: obra.id }) : await crearObra(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(obra ? "Obra actualizada" : "Obra creada");
    onClose();
  }

  return (
    <RightPanel
      title={obra ? "Modificar obra" : "Nueva obra"}
      subtitle={obra?.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="submit"
            form="form-obra"
            className="btn btn-primary btn-sm"
            disabled={enviando}
          >
            {enviando ? "Guardando…" : obra ? "Guardar cambios" : "Crear obra"}
          </button>
        </>
      }
    >
      <form
        id="form-obra"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Nombre</label>
          <input
            aria-required
            className={`input ${errors.nombre ? "input-error" : ""}`}
            {...register("nombre")}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <AvisoDuplicados items={duplicados} />

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

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Tipo</label>
            <select className="input" {...register("tipo")}>
              {TIPOS_OBRA.map((tipo) => (
                <option key={tipo} value={tipo}>
                  {TIPO_OBRA_LABEL[tipo]}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="t-label mb-1 block">Estado de obra</label>
            <select className="input" {...register("estado_obra")}>
              {ESTADOS_OBRA.map((estado) => (
                <option key={estado} value={estado}>
                  {ESTADO_OBRA_LABEL[estado]}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Unidades</label>
            <input
              type="number"
              min={1}
              className={`input ${errors.cantidad_unidades ? "input-error" : ""}`}
              {...register("cantidad_unidades")}
            />
            {errors.cantidad_unidades && (
              <p className="input-error-text">{errors.cantidad_unidades.message}</p>
            )}
          </div>
          <div>
            <label className="t-label mb-1 block">Superficie (m²)</label>
            <input
              type="number"
              step="0.01"
              min={0}
              className={`input ${errors.superficie_estimada ? "input-error" : ""}`}
              {...register("superficie_estimada")}
            />
            {errors.superficie_estimada && (
              <p className="input-error-text">{errors.superficie_estimada.message}</p>
            )}
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Inicio estimado</label>
          <input type="date" className="input" {...register("fecha_estimada_inicio")} />
        </div>

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
