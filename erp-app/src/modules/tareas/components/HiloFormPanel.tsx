"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearHilo } from "../actions";
import { crearHiloSchema, type CrearHiloForm } from "../types";
import type { TareaProyecto, Usuario } from "../types";

export function HiloFormPanel({
  usuarios,
  proyectos,
  usuarioActualId,
  proyectoId,
  onClose,
}: {
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  usuarioActualId: string | null;
  proyectoId?: string;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<CrearHiloForm>({
    resolver: zodResolver(crearHiloSchema),
    defaultValues: {
      proyecto_id: proyectoId ?? null,
      visibilidad: "privado",
      responsable_id: usuarioActualId ?? "",
    },
  });

  async function onSubmit(data: CrearHiloForm) {
    setEnviando(true);
    const result = await crearHilo(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Hilo creado");
    onClose();
  }

  return (
    <RightPanel
      title="Nuevo hilo"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-hilo" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Creando…" : "Crear hilo"}
          </button>
        </>
      }
    >
      <form
        id="form-hilo"
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

        {!proyectoId && (
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

        <div>
          <label className="t-label mb-1 block">Responsable</label>
          <select className={`input ${errors.responsable_id ? "input-error" : ""}`} {...register("responsable_id")}>
            <option value="">— seleccionar —</option>
            {usuarios.map((u) => (
              <option key={u.id} value={u.id}>
                {u.nombre}
              </option>
            ))}
          </select>
          {errors.responsable_id && <p className="input-error-text">{errors.responsable_id.message}</p>}
        </div>
      </form>
    </RightPanel>
  );
}
