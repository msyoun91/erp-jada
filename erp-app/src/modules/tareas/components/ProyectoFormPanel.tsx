"use client";

import { useState } from "react";
import { useForm, useController } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearProyecto, editarProyecto } from "../actions";
import { crearProyectoSchema, type CrearProyectoForm } from "../types";
import type { TareaProyecto } from "../types";
import { useTareasContexto } from "./tareasContexto";

// Crear y modificar en el mismo panel (prop `proyecto`), mismo patrón que
// TareaFormPanel/PlantillaFormPanel. Los miembros se editan acá: son una
// característica más del proyecto, no una pantalla aparte — pero quién puede
// tocarlos es su propia función (`tareas_proyectos_miembros`). Sin ella el
// bloque no se muestra y la membresía viaja como default oculto, igual que
// proyecto/visibilidad en HiloFormPanel.
export function ProyectoFormPanel({
  proyecto,
  miembrosActuales,
  gestionarMiembros,
  onClose,
}: {
  proyecto?: TareaProyecto;
  miembrosActuales?: string[];
  gestionarMiembros: boolean;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { usuarios, usuarioActualId } = useTareasContexto();
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<CrearProyectoForm>({
    resolver: zodResolver(crearProyectoSchema),
    defaultValues: proyecto
      ? {
          nombre: proyecto.nombre,
          descripcion: proyecto.descripcion ?? undefined,
          visibilidad: proyecto.visibilidad,
          miembros: miembrosActuales ?? [],
        }
      : { visibilidad: "privado", miembros: usuarioActualId ? [usuarioActualId] : [] },
  });

  const miembrosField = useController({ name: "miembros", control });
  const seleccionados = miembrosField.field.value ?? [];

  function toggle(id: string) {
    miembrosField.field.onChange(
      seleccionados.includes(id) ? seleccionados.filter((x) => x !== id) : [...seleccionados, id]
    );
  }

  async function onSubmit(data: CrearProyectoForm) {
    setEnviando(true);
    const result = proyecto ? await editarProyecto({ ...data, id: proyecto.id }) : await crearProyecto(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(proyecto ? "Proyecto actualizado" : "Proyecto creado");
    onClose();
  }

  return (
    <RightPanel
      title={proyecto ? "Modificar proyecto" : "Nuevo proyecto"}
      subtitle={proyecto?.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-proyecto" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : proyecto ? "Guardar cambios" : "Crear proyecto"}
          </button>
        </>
      }
    >
      <form
        id="form-proyecto"
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

        <div>
          <label className="t-label mb-1 block">Descripción</label>
          <textarea rows={3} className="input" {...register("descripcion")} />
        </div>

        <div>
          <label className="t-label mb-1 block">Visibilidad</label>
          <select className="input" {...register("visibilidad")}>
            <option value="privado">Privada</option>
            <option value="publico">Pública</option>
          </select>
        </div>

        {gestionarMiembros && (
          <div>
            <label className="t-label t-label-req mb-1 block">Miembros</label>
            <p className="t-caption mb-1">Solo los miembros pueden recibir tareas del proyecto.</p>
            <div className="max-h-40 overflow-y-auto rounded-md border-[1.5px] border-border-strong">
              {usuarios.map((u) => (
                <label
                  key={u.id}
                  className="tap-target flex cursor-pointer items-center gap-2 px-3 py-2 hover:bg-bg-subtle"
                >
                  <input
                    type="checkbox"
                    checked={seleccionados.includes(u.id)}
                    onChange={() => toggle(u.id)}
                    className="h-4 w-4 shrink-0 accent-brand-700"
                  />
                  <span className="t-body-m">{u.nombre}</span>
                </label>
              ))}
            </div>
            {errors.miembros && <p className="input-error-text">{errors.miembros.message}</p>}
          </div>
        )}
      </form>
    </RightPanel>
  );
}
