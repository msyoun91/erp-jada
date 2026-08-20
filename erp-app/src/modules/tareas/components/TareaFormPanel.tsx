"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearTarea, editarTarea } from "../actions";
import { crearTareaSchema, type CrearTareaForm } from "../types";
import type { TareaConAsignados, TareaProyecto, Usuario } from "../types";
import { AsignadosPicker } from "./AsignadosPicker";
import { puedeTrabajarEnProyecto } from "./proyectoTareas";
import { hoyISO, sumarDiasISO } from "@/lib/utils";

const VENCIMIENTO_PRESETS = [1, 3, 7];

// Un solo panel para crear y editar: con `tarea` presente pasa a modo
// edición. El schema sigue siendo crearTareaSchema (superset del de edición).
// Los asignados se editan acá igual que al crear — sin la función
// `tareas_asignar` el picker no aparece y viajan como defaults ocultos.
export function TareaFormPanel({
  usuarios,
  proyectos,
  miembrosPorProyecto,
  usuarioActualId,
  puedeAsignar,
  hiloId,
  proyectoId,
  proyectoHeredadoId,
  tarea,
  onClose,
}: {
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  miembrosPorProyecto: Record<string, string[]>;
  usuarioActualId: string | null;
  puedeAsignar: boolean;
  hiloId?: string;
  proyectoId?: string;
  // Proyecto del hilo al que se agrega la tarea: la tarea no lo guarda (lo
  // hereda), pero limita igual quiénes pueden recibirla.
  proyectoHeredadoId?: string | null;
  tarea?: TareaConAsignados;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const [tieneRecurrencia, setTieneRecurrencia] = useState(tarea?.recurrencia_cantidad != null);
  const proyectosDisponibles = proyectos.filter((p) =>
    puedeTrabajarEnProyecto(miembrosPorProyecto[p.id] ?? [], usuarioActualId, puedeAsignar)
  );
  const proyectoInicial = proyectoHeredadoId ?? proyectoId ?? tarea?.proyecto_id ?? null;
  const miembrosIniciales = proyectoInicial ? (miembrosPorProyecto[proyectoInicial] ?? []) : null;
  // Auto-asignarse solo si el usuario puede trabajar en ese proyecto.
  const autoAsignado =
    usuarioActualId && (!miembrosIniciales || miembrosIniciales.includes(usuarioActualId))
      ? usuarioActualId
      : null;
  const {
    register,
    handleSubmit,
    control,
    setValue,
    getValues,
    formState: { errors, dirtyFields },
  } = useForm<CrearTareaForm>({
    resolver: zodResolver(crearTareaSchema),
    defaultValues: tarea
      ? {
          titulo: tarea.titulo,
          descripcion: tarea.descripcion ?? undefined,
          hilo_id: tarea.hilo_id,
          proyecto_id: tarea.proyecto_id,
          visibilidad: tarea.visibilidad,
          responsable_id: tarea.responsable_id,
          asignados: tarea.tareas_asignados.filter((a) => a.activo).map((a) => a.usuario_id),
          fecha_vencimiento: tarea.fecha_vencimiento,
          temperatura: tarea.temperatura,
          recurrencia_cantidad: tarea.recurrencia_cantidad,
          recurrencia_unidad: tarea.recurrencia_unidad,
        }
      : {
          hilo_id: hiloId ?? null,
          proyecto_id: proyectoId ?? null,
          // Lo que vive en un proyecto es del equipo del proyecto: con proyecto
          // el default es público. Sigue siendo un default, no una regla.
          visibilidad: proyectoInicial ? "publico" : "privado",
          responsable_id: autoAsignado ?? "",
          asignados: autoAsignado ? [autoAsignado] : [],
          temperatura: 50,
        },
  });

  const proyectoElegido = useWatch({ control, name: "proyecto_id" });
  const proyectoEfectivo = proyectoHeredadoId ?? proyectoElegido ?? null;
  const miembros = proyectoEfectivo ? (miembrosPorProyecto[proyectoEfectivo] ?? []) : null;

  // Cambiar de proyecto cambia quiénes pueden recibir la tarea: los ya
  // seleccionados que no son miembros del nuevo proyecto se descartan. Y mueve
  // el default de visibilidad, salvo que el usuario ya lo haya tocado.
  function alCambiarProyecto(nuevoProyectoId: string) {
    if (!dirtyFields.visibilidad) {
      setValue("visibilidad", nuevoProyectoId ? "publico" : "privado");
    }

    const permitidos = nuevoProyectoId ? (miembrosPorProyecto[nuevoProyectoId] ?? []) : null;
    if (!permitidos) return;
    const validos = (getValues("asignados") ?? []).filter((id) => permitidos.includes(id));
    setValue("asignados", validos);
    if (!validos.includes(getValues("responsable_id"))) setValue("responsable_id", validos[0] ?? "");
  }

  async function onSubmit(data: CrearTareaForm) {
    setEnviando(true);
    const result = tarea ? await editarTarea({ ...data, id: tarea.id }) : await crearTarea(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(tarea ? "Tarea actualizada" : "Tarea creada");
    onClose();
  }

  return (
    <RightPanel
      title={tarea ? "Editar tarea" : "Nueva tarea"}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-tarea" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : tarea ? "Guardar" : "Crear tarea"}
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

        {!hiloId && !proyectoId && !tarea?.hilo_id && (
          <div>
            <label className="t-label mb-1 block">Proyecto</label>
            <select
              className="input"
              {...register("proyecto_id", { onChange: (e) => alCambiarProyecto(e.target.value) })}
            >
              <option value="">Sin proyecto</option>
              {/* Un proyecto donde no podés trabajar deja el form sin asignado
                  posible: elegirlo era un callejón sin salida. */}
              {proyectosDisponibles.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.nombre}
                </option>
              ))}
            </select>
          </div>
        )}

        {/* Dentro de un hilo la visibilidad la decide el hilo: `tareas_select`
            solo lee `tareas.visibilidad` con `hilo_id IS NULL` (sql/013). El
            valor viaja como default oculto — vuelve a mandar si la tarea sale
            del hilo. */}
        {!hiloId && !tarea?.hilo_id && (
          <div>
            <label className="t-label mb-1 block">Visibilidad</label>
            <select className="input" {...register("visibilidad")}>
              <option value="privado">Privada</option>
              <option value="publico">Pública</option>
            </select>
          </div>
        )}

        <AsignadosPicker
          control={control}
          usuarios={usuarios}
          miembros={miembros}
          puedeAsignar={puedeAsignar}
        />

        <div>
          <label className="t-label mb-1 block">Vencimiento</label>
          <input type="date" className="input" {...register("fecha_vencimiento")} />
          <div className="mt-2 flex flex-wrap gap-2">
            {VENCIMIENTO_PRESETS.map((dias) => (
              <button
                key={dias}
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => setValue("fecha_vencimiento", sumarDiasISO(hoyISO(), dias))}
              >
                {dias} {dias === 1 ? "día" : "días"}
              </button>
            ))}
          </div>
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
