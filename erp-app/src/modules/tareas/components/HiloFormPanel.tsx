"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearHilo, editarHilo } from "../actions";
import { crearHiloSchema, type CrearHiloForm } from "../types";
import type { TareaHilo, TareaProyecto, Usuario } from "../types";

// Un solo panel para crear y editar (prop `hilo`), mismo patrón que
// TareaFormPanel: el schema sigue siendo crearHiloSchema (superset) y en
// edición proyecto/responsable viajan como defaults ocultos. Editar toca
// título, descripción y visibilidad — mover el hilo de proyecto cambiaría
// quiénes pueden trabajar en sus tareas, y esa validación existe sobre
// `tareas` (sql/009), no sobre el hilo; la visibilidad no toca la membresía.
export function HiloFormPanel({
  usuarios,
  proyectos,
  usuarioActualId,
  proyectoId,
  hilo,
  onClose,
}: {
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  usuarioActualId: string | null;
  proyectoId?: string;
  hilo?: TareaHilo;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    setValue,
    formState: { errors, dirtyFields },
  } = useForm<CrearHiloForm>({
    resolver: zodResolver(crearHiloSchema),
    defaultValues: hilo
      ? {
          titulo: hilo.titulo,
          descripcion: hilo.descripcion ?? undefined,
          proyecto_id: hilo.proyecto_id,
          visibilidad: hilo.visibilidad,
          responsable_id: hilo.responsable_id,
        }
      : {
          proyecto_id: proyectoId ?? null,
          // Lo que vive en un proyecto es del equipo del proyecto: con proyecto
          // el default es público. Sigue siendo un default, no una regla.
          visibilidad: proyectoId ? "publico" : "privado",
          responsable_id: usuarioActualId ?? "",
        },
  });

  // Elegir proyecto después de abrir el panel mueve el default igual que si se
  // hubiera abierto desde el proyecto — salvo que el usuario ya lo haya tocado.
  function sincronizarVisibilidad(nuevoProyectoId: string) {
    if (dirtyFields.visibilidad) return;
    setValue("visibilidad", nuevoProyectoId ? "publico" : "privado");
  }

  async function onSubmit(data: CrearHiloForm) {
    setEnviando(true);
    const result = hilo
      ? await editarHilo({
          id: hilo.id,
          titulo: data.titulo,
          descripcion: data.descripcion,
          visibilidad: data.visibilidad ?? hilo.visibilidad,
        })
      : await crearHilo(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(hilo ? "Hilo actualizado" : "Hilo creado");
    onClose();
  }

  return (
    <RightPanel
      title={hilo ? "Modificar hilo" : "Nuevo hilo"}
      subtitle={hilo?.titulo}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-hilo" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : hilo ? "Guardar cambios" : "Crear hilo"}
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

        {!hilo && !proyectoId && (
          <div>
            <label className="t-label mb-1 block">Proyecto</label>
            <select
              className="input"
              {...register("proyecto_id", { onChange: (e) => sincronizarVisibilidad(e.target.value) })}
            >
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

        {!hilo && (
          <div>
            <label className="t-label mb-1 block">Responsable</label>
            <select
              className={`input ${errors.responsable_id ? "input-error" : ""}`}
              {...register("responsable_id")}
            >
              <option value="">— seleccionar —</option>
              {usuarios.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre}
                </option>
              ))}
            </select>
            {errors.responsable_id && <p className="input-error-text">{errors.responsable_id.message}</p>}
          </div>
        )}
      </form>
    </RightPanel>
  );
}
