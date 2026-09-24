"use client";

import { useState } from "react";
import { useForm, useWatch, type Resolver } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearPaso, editarPaso, insertarPasoAntes } from "../actions";
import { editarPasoSchema, insertarAntesSchema, pasoSchema, type Tarea } from "../types";
import { AsignadoSelect } from "./AsignadoSelect";
import { Campo, claseInput } from "./Campo";

export type ModoPaso =
  | { tipo: "sumar"; hiloId: string; colas: Tarea[]; soloYo: boolean }
  | { tipo: "antes"; siguiente: Tarea }
  | { tipo: "editar"; paso: Tarea };

type Valores = {
  id?: string;
  hilo_id?: string;
  siguiente_id?: string;
  paso_anterior_id?: string | null;
  titulo: string;
  descripcion?: string | null;
  prioridad?: "baja" | "media" | "alta";
  vence?: string | null;
  vence_dias?: number | string | null;
  asignado_id?: string | null;
  asignado_equipo_id?: string | null;
};

const SCHEMA = { sumar: pasoSchema, antes: insertarAntesSchema, editar: editarPasoSchema };
const TITULO = { sumar: "Sumar paso", antes: "Insertar paso antes", editar: "Editar paso" };
const FORM_ID = "paso-form";

function iniciales(modo: ModoPaso, yo: string): Valores {
  if (modo.tipo === "editar") {
    const p = modo.paso;
    return {
      id: p.id,
      titulo: p.titulo,
      descripcion: p.descripcion ?? "",
      prioridad: p.prioridad,
      // Con plazo en días, `vence` lo calcula la base: se edita uno u otro.
      vence: p.vence_dias ? "" : (p.vence ?? ""),
      vence_dias: p.vence_dias ?? "",
    };
  }
  const base = { titulo: "", descripcion: "", prioridad: "media" as const, vence: "", vence_dias: "" };
  const asignado = { asignado_id: yo, asignado_equipo_id: null };
  if (modo.tipo === "antes") return { ...base, ...asignado, siguiente_id: modo.siguiente.id };
  return { ...base, ...asignado, hilo_id: modo.hiloId, paso_anterior_id: "" };
}

export function PasoFormPanel({ modo, yo, onClose }: { modo: ModoPaso; yo: string; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    setValue,
    formState: { errors, isDirty },
  } = useForm<Valores>({
    // Cada modo valida con el schema de su action; los campos de más se descartan.
    resolver: zodResolver(SCHEMA[modo.tipo]) as unknown as Resolver<Valores>,
    defaultValues: iniciales(modo, yo),
  });

  const [previo, asignadoId, asignadoEquipoId] = useWatch({
    control,
    name: ["paso_anterior_id", "asignado_id", "asignado_equipo_id"],
  });
  const conPrevio =
    modo.tipo === "sumar"
      ? !!previo
      : modo.tipo === "antes"
        ? modo.siguiente.paso_anterior_id !== null
        : modo.paso.paso_anterior_id !== null;

  async function onSubmit(data: Valores) {
    setEnviando(true);
    const result =
      modo.tipo === "sumar"
        ? await crearPaso(data as Parameters<typeof crearPaso>[0])
        : modo.tipo === "antes"
          ? await insertarPasoAntes(data as Parameters<typeof insertarPasoAntes>[0])
          : await editarPaso(data as Parameters<typeof editarPaso>[0]);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(modo.tipo === "editar" ? "Paso guardado" : "Paso sumado");
    onClose();
  }

  return (
    <RightPanel
      title={TITULO[modo.tipo]}
      subtitle={modo.tipo === "antes" ? `Antes de "${modo.siguiente.titulo}"` : undefined}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <div className="flex-1" />
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : modo.tipo === "editar" ? "Guardar" : "Sumar paso"}
          </button>
        </>
      }
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <Campo id="paso-titulo" label="Título" requerido error={errors.titulo}>
          <input id="paso-titulo" aria-required className={claseInput(errors.titulo)} {...register("titulo")} />
        </Campo>

        <Campo id="paso-descripcion" label="Descripción" error={errors.descripcion}>
          <textarea
            id="paso-descripcion"
            rows={4}
            className={claseInput(errors.descripcion)}
            {...register("descripcion")}
          />
        </Campo>

        {modo.tipo !== "editar" && (
          <Campo id="paso-asignado" label="Asignado" requerido error={errors.asignado_id}>
            <AsignadoSelect
              id="paso-asignado"
              soloYo={modo.tipo === "sumar" && modo.soloYo}
              invalido={!!errors.asignado_id}
              value={{ asignado_id: asignadoId ?? null, asignado_equipo_id: asignadoEquipoId ?? null }}
              onChange={(v) => {
                setValue("asignado_id", v.asignado_id, { shouldDirty: true });
                setValue("asignado_equipo_id", v.asignado_equipo_id, { shouldDirty: true });
              }}
            />
          </Campo>
        )}

        {modo.tipo === "sumar" && !modo.soloYo && (
          <Campo id="paso-previo" label="Espera a" error={errors.paso_anterior_id}>
            <select id="paso-previo" className="input" {...register("paso_anterior_id")}>
              <option value="">Nada: en paralelo</option>
              {modo.colas.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.titulo}
                </option>
              ))}
            </select>
          </Campo>
        )}

        <Campo id="paso-prioridad" label="Prioridad" error={errors.prioridad}>
          <select id="paso-prioridad" className="input" {...register("prioridad")}>
            <option value="alta">Alta</option>
            <option value="media">Media</option>
            <option value="baja">Baja</option>
          </select>
        </Campo>

        <div className="flex gap-3">
          <div className="flex-1">
            <Campo id="paso-vence" label="Vence" error={errors.vence}>
              <input id="paso-vence" type="date" className={claseInput(errors.vence)} {...register("vence")} />
            </Campo>
          </div>
          {conPrevio && (
            <div className="flex-1">
              <Campo id="paso-dias" label="O días desde que se habilita" error={errors.vence_dias}>
                <input
                  id="paso-dias"
                  type="number"
                  min={1}
                  className={claseInput(errors.vence_dias)}
                  {...register("vence_dias")}
                />
              </Campo>
            </div>
          )}
        </div>
      </form>
    </RightPanel>
  );
}
