"use client";

import { useState } from "react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { usarPlantilla } from "../actions";
import {
  EJECUTOR,
  usarPlantillaSchema,
  type PlantillaCompleta,
  type TareaPlantillaItem,
  type UsarPlantillaForm,
} from "../types";
import { puedeTrabajarEnProyecto } from "./proyectoTareas";
import { temperaturaRango } from "./tareaLabels";
import { useTareasContexto } from "./tareasContexto";

// Desde la vista Plantillas (sin destino: la de proyecto crea el suyo, las de
// hilo y tarea van sueltas o a un proyecto) o desde un hilo (`hiloId`: los
// pasos se suman a ese hilo). Qué recibe cada paso lo decide `usar_plantilla`
// — acá solo se muestra lo que la plantilla pide.
export function UsarPlantillaPanel({
  plantillas,
  plantillaId,
  hiloId,
  onClose,
}: {
  plantillas: PlantillaCompleta[];
  plantillaId?: string;
  hiloId?: string;
  onClose: () => void;
}) {
  const { proyectos, miembrosPorProyecto, usuarioActualId, puedeAsignar, usuarios } = useTareasContexto();
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<UsarPlantillaForm>({
    resolver: zodResolver(usarPlantillaSchema),
    defaultValues: { plantilla_id: plantillaId ?? "", hilo_id: hiloId ?? null, proyecto_id: null },
  });

  const plantillaElegida = useWatch({ control, name: "plantilla_id" });
  const elegida = plantillas.find((p) => p.id === plantillaElegida);
  const proyectosDisponibles = proyectos.filter((p) =>
    puedeTrabajarEnProyecto(miembrosPorProyecto[p.id] ?? [], usuarioActualId, puedeAsignar),
  );
  const pideTitulo = elegida?.tipo === "proyecto" || (elegida?.tipo === "hilo" && !hiloId);
  const pideProyecto = elegida !== undefined && elegida.tipo !== "proyecto" && !hiloId;

  const nombreDe = (id: string) =>
    id === EJECUTOR ? "vos" : (usuarios.find((u) => u.id === id)?.nombre ?? "usuario inactivo");

  async function onSubmit(data: UsarPlantillaForm) {
    setEnviando(true);
    const result = await usarPlantilla({ ...data, proyecto_id: pideProyecto ? data.proyecto_id : null });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(
      elegida?.tipo === "proyecto" ? "Proyecto creado desde la plantilla" : "Plantilla usada",
    );
    if (result.derivados) {
      toast.warning(
        result.derivados === 1
          ? "Un paso quedó para vos: sus asignados no podían recibirlo. Tiene una nota con el motivo."
          : `${result.derivados} pasos quedaron para vos: sus asignados no podían recibirlos. Cada uno tiene una nota con el motivo.`,
      );
    }
    onClose();
  }

  return (
    <RightPanel
      title="Usar plantilla"
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-usar-plantilla" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Creando…" : "Crear"}
          </button>
        </>
      }
    >
      <form
        id="form-usar-plantilla"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Plantilla</label>
          <select
            aria-required
            className={`input ${errors.plantilla_id ? "input-error" : ""}`}
            {...register("plantilla_id")}
          >
            <option value="">— seleccionar —</option>
            {plantillas.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nombre}
              </option>
            ))}
          </select>
          {errors.plantilla_id && <p className="input-error-text">{errors.plantilla_id.message}</p>}
        </div>

        {pideTitulo && (
          <div>
            <label className="t-label mb-1 block">
              {elegida?.tipo === "proyecto" ? "Nombre del proyecto" : "Título del hilo"}
            </label>
            <input className="input" placeholder={elegida?.titulo_creado ?? elegida?.nombre} {...register("titulo")} />
            <p className="t-caption mt-1">Vacío = el que define la plantilla.</p>
          </div>
        )}

        {pideProyecto && (
          <div>
            <label className="t-label mb-1 block">Proyecto</label>
            <select className="input" {...register("proyecto_id")}>
              <option value="">Sin proyecto</option>
              {proyectosDisponibles.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.nombre}
                </option>
              ))}
            </select>
          </div>
        )}

        {elegida && (
          <div className="rounded-lg border border-border p-3">
            <p className="t-label mb-2">Se va a crear</p>
            {elegida.tipo === "proyecto" && (
              <p className="t-body-m mb-2">
                Un proyecto {elegida.visibilidad === "publico" ? "público" : "privado"} con{" "}
                {[...elegida.miembros.map(nombreDe), "vos"].join(", ")} como miembros.
              </p>
            )}
            {elegida.hilos.map((h) => (
              <div key={h.id} className="mb-2">
                <p className="t-body-m font-medium">Hilo «{h.titulo}»</p>
                <ListaVista items={elegida.items.filter((i) => i.hilo_id === h.id)} ordenada={h.encadenada} nombreDe={nombreDe} />
              </div>
            ))}
            {elegida.items.some((i) => !i.hilo_id) && (
              <div>
                {elegida.tipo === "proyecto" && <p className="t-body-m font-medium">Tareas sueltas</p>}
                {elegida.tipo === "hilo" && (
                  <p className="t-body-m font-medium">{hiloId ? "Pasos en este hilo" : "Un hilo con estos pasos"}</p>
                )}
                <ListaVista
                  items={elegida.items.filter((i) => !i.hilo_id)}
                  ordenada={elegida.tipo === "hilo" && elegida.encadenada}
                  nombreDe={nombreDe}
                />
              </div>
            )}
            {(elegida.tipo === "hilo" ? elegida.encadenada : elegida.hilos.some((h) => h.encadenada)) && (
              <p className="t-caption mt-2">Los pasos numerados se crean encadenados: cada uno se habilita al completar el anterior.</p>
            )}
            <p className="t-caption mt-2">
              Si alguien no puede recibir un paso (inactivo, fuera del proyecto o sin permiso para asignarle), se
              descarta; si el paso se queda sin nadie, queda para vos con una nota.
            </p>
          </div>
        )}
      </form>
    </RightPanel>
  );
}

function ListaVista({
  items,
  ordenada,
  nombreDe,
}: {
  items: TareaPlantillaItem[];
  ordenada: boolean;
  nombreDe: (id: string) => string;
}) {
  const Lista = ordenada ? "ol" : "ul";
  return (
    <Lista className={`t-caption flex flex-col gap-1 pl-5 ${ordenada ? "list-decimal" : "list-disc"}`}>
      {items.map((i, n) => {
        const asignados = [...(i.incluir_ejecutor ? [EJECUTOR] : []), ...i.asignados].map(nombreDe).join(", ");
        // El primero de una cadena no tiene anterior: su plazo corre desde que se crea.
        const trasPrevio = i.vence_tras_previo && ordenada && n > 0;
        const vence =
          i.vence_dias == null
            ? null
            : `vence ${i.vence_dias} d ${trasPrevio ? "después del anterior" : "después de creada"}`;
        return (
          <li key={i.id}>
            <span className="text-text-primary">{i.titulo}</span>
            {" — "}
            {[asignados, vence, `temperatura ${temperaturaRango(i.temperatura).label.toLowerCase()}`]
              .filter(Boolean)
              .join(" · ")}
          </li>
        );
      })}
    </Lista>
  );
}
