"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import type { UsuarioBasico } from "@/lib/usuarios";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearProspecto, editarProspecto } from "../actions";
import {
  ESTADOS_PROSPECTO,
  MONEDAS,
  prospectoSchema,
  type Fuente,
  type ObraConRelaciones,
  type ProspectoForm,
  type ProspectoListado,
} from "../types";
import { ESTADO_PROSPECTO_LABEL } from "./comercialLabels";

export function ProspectoFormPanel({
  prospecto,
  obras,
  obrasConProspecto,
  fuentes,
  usuarios,
  usuarioActualId,
  gestionarAjenos,
  onClose,
}: {
  prospecto?: ProspectoListado;
  obras: ObraConRelaciones[];
  obrasConProspecto: string[];
  fuentes: Fuente[];
  usuarios: UsuarioBasico[];
  usuarioActualId: string | null;
  gestionarAjenos: boolean;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<ProspectoForm>({
    resolver: zodResolver(prospectoSchema),
    defaultValues: prospecto
      ? {
          obra_id: prospecto.obra_id,
          estado_prospecto: prospecto.estado_prospecto,
          fuente_id: prospecto.fuente_id ?? "",
          responsable_id: prospecto.responsable_id,
          potencial_estimado: prospecto.potencial_estimado ?? "",
          moneda_potencial: prospecto.moneda_potencial ?? "",
          fecha_estimada_compra: prospecto.fecha_estimada_compra,
          observaciones: prospecto.observaciones,
        }
      : {
          estado_prospecto: "nuevo",
          responsable_id: usuarioActualId ?? "",
          potencial_estimado: "",
          moneda_potencial: "",
        },
  });

  // Una obra tiene un prospecto activo a lo sumo. Las que ya tienen uno no se
  // ofrecen — el unique parcial las rechazaría igual, pero con un error crudo.
  const obrasDisponibles = obras.filter(
    (o) => o.id === prospecto?.obra_id || !obrasConProspecto.includes(o.id)
  );

  async function onSubmit(data: ProspectoForm) {
    setEnviando(true);
    const result = prospecto
      ? await editarProspecto({ ...data, id: prospecto.id })
      : await crearProspecto(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(prospecto ? "Prospecto actualizado" : "Prospecto creado");
    onClose();
  }

  return (
    <RightPanel
      title={prospecto ? "Modificar prospecto" : "Nuevo prospecto"}
      subtitle={prospecto?.obras?.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            type="submit"
            form="form-prospecto"
            className="btn btn-primary btn-sm"
            disabled={enviando}
          >
            {enviando ? "Guardando…" : prospecto ? "Guardar cambios" : "Crear prospecto"}
          </button>
        </>
      }
    >
      <form
        id="form-prospecto"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Obra</label>
          <select
            aria-required
            className={`input ${errors.obra_id ? "input-error" : ""}`}
            disabled={Boolean(prospecto)}
            {...register("obra_id")}
          >
            <option value="">Elegí una obra</option>
            {obrasDisponibles.map((o) => (
              <option key={o.id} value={o.id}>
                {[o.nombre, o.localidad].filter(Boolean).join(" — ")}
              </option>
            ))}
          </select>
          {errors.obra_id && <p className="input-error-text">{errors.obra_id.message}</p>}
          {!prospecto && (
            <p className="t-caption mt-1">
              La obra se carga primero en la pestaña Obras. Empresas y personas se relacionan ahí.
            </p>
          )}
        </div>

        <div>
          <label className="t-label mb-1 block">Estado del prospecto</label>
          <select className="input" {...register("estado_prospecto")}>
            {ESTADOS_PROSPECTO.map((estado) => (
              <option key={estado} value={estado}>
                {ESTADO_PROSPECTO_LABEL[estado]}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="t-label mb-1 block">Fuente</label>
          <select className="input" {...register("fuente_id")}>
            <option value="">Sin fuente</option>
            {fuentes.map((f) => (
              <option key={f.id} value={f.id}>
                {f.nombre}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="t-label t-label-req mb-1 block">Responsable comercial</label>
          <select
            className={`input ${errors.responsable_id ? "input-error" : ""}`}
            disabled={!gestionarAjenos}
            {...register("responsable_id")}
          >
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
          {errors.responsable_id && (
            <p className="input-error-text">{errors.responsable_id.message}</p>
          )}
          {!gestionarAjenos && (
            <p className="t-caption mt-1">
              Pasarle el prospecto a otro necesita la función de prospectos ajenos.
            </p>
          )}
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="t-label mb-1 block">Potencial estimado</label>
            <input
              type="number"
              step="0.01"
              min={0}
              className={`input ${errors.potencial_estimado ? "input-error" : ""}`}
              {...register("potencial_estimado")}
            />
            {errors.potencial_estimado && (
              <p className="input-error-text">{errors.potencial_estimado.message}</p>
            )}
          </div>
          <div>
            <label className="t-label mb-1 block">Moneda</label>
            <select
              className={`input ${errors.moneda_potencial ? "input-error" : ""}`}
              {...register("moneda_potencial")}
            >
              <option value="">—</option>
              {MONEDAS.map((m) => (
                <option key={m} value={m}>
                  {m}
                </option>
              ))}
            </select>
            {errors.moneda_potencial && (
              <p className="input-error-text">{errors.moneda_potencial.message}</p>
            )}
          </div>
        </div>

        <div>
          <label className="t-label mb-1 block">Compra estimada</label>
          <input type="date" className="input" {...register("fecha_estimada_compra")} />
        </div>

        <div>
          <label className="t-label mb-1 block">Observaciones</label>
          <textarea rows={3} className="input" {...register("observaciones")} />
        </div>
      </form>
    </RightPanel>
  );
}
