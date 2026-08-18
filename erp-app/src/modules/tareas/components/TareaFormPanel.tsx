"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearTarea } from "../actions";
import { crearTareaSchema, type CrearTareaForm } from "../types";
import type { TareaProyecto, Usuario } from "../types";
import { AsignadosPicker } from "./AsignadosPicker";

export function TareaFormPanel({
  usuarios,
  proyectos,
  usuarioActualId,
  hiloId,
  proyectoId,
  onClose,
}: {
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  usuarioActualId: string | null;
  hiloId?: string;
  proyectoId?: string;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const [tieneRecurrencia, setTieneRecurrencia] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    setValue,
    formState: { errors },
  } = useForm<CrearTareaForm>({
    resolver: zodResolver(crearTareaSchema),
    defaultValues: {
      hilo_id: hiloId ?? null,
      proyecto_id: proyectoId ?? null,
      visibilidad: "privado",
      responsable_id: usuarioActualId ?? "",
      asignados: usuarioActualId ? [usuarioActualId] : [],
      temperatura: 50,
    },
  });

  async function onSubmit(data: CrearTareaForm) {
    setEnviando(true);
    const result = await crearTarea(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea creada");
    onClose();
  }

  return (
    <RightPanel
      title="Nueva tarea"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-tarea" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Creando…" : "Crear tarea"}
          </button>
        </>
      }
    >
      <form
        id="form-tarea"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label mb-1 block">Título</label>
          <input className={`input ${errors.titulo ? "input-error" : ""}`} {...register("titulo")} />
          {errors.titulo && <p className="input-error-text">{errors.titulo.message}</p>}
        </div>

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea rows={3} className="input" {...register("descripcion")} />
        </div>

        {!hiloId && !proyectoId && (
          <div>
            <label className="t-label mb-1 block">Proyecto</label>
            <select className="input" {...register("proyecto_id")}>
              <option value="">Sin proyecto</option>
              {proyectos.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.nombre}
                </option>
              ))}
            </select>
          </div>
        )}

        <div>
          <label className="t-label mb-1 block">Visibilidad</label>
          <select className="input" {...register("visibilidad")}>
            <option value="privado">Privada</option>
            <option value="publico">Pública</option>
          </select>
        </div>

        <AsignadosPicker control={control} usuarios={usuarios} />

        <div>
          <label className="t-label mb-1 block">Vencimiento</label>
          <input type="date" className="input" {...register("fecha_vencimiento")} />
        </div>

        <div>
          <label className="t-label mb-1 block">Temperatura</label>
          <input type="range" min={1} max={100} className="w-full accent-brand-700" {...register("temperatura")} />
        </div>

        <div>
          <label className="flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              checked={tieneRecurrencia}
              onChange={(e) => {
                setTieneRecurrencia(e.target.checked);
                if (!e.target.checked) {
                  setValue("recurrencia_cantidad", null);
                  setValue("recurrencia_unidad", null);
                }
              }}
              className="h-4 w-4 accent-brand-700"
            />
            <span className="t-body-m">Se repite</span>
          </label>
        </div>

        {tieneRecurrencia && (
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="t-label mb-1 block">Cada</label>
              <input
                type="number"
                min={1}
                className={`input ${errors.recurrencia_cantidad ? "input-error" : ""}`}
                {...register("recurrencia_cantidad")}
              />
            </div>
            <div className="flex-1">
              <label className="t-label mb-1 block">Unidad</label>
              <select className="input" {...register("recurrencia_unidad")}>
                <option value="dia">Día(s)</option>
                <option value="mes">Mes(es)</option>
              </select>
            </div>
          </div>
        )}
      </form>
    </RightPanel>
  );
}
