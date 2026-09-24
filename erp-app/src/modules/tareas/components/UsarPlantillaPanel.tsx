"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { usarPlantilla } from "../actions";
import { motivoRevisar } from "../derivados";
import type { PlantillaCompleta } from "../queries";
import { usarPlantillaSchema, type UsarPlantillaForm } from "../types";
import { AsignadoSelect } from "./AsignadoSelect";
import { Campo, claseInput } from "./Campo";
import { useNombre, useTareas } from "./contexto";

const FORM_ID = "usar-plantilla-form";

// Pregunta por los pasos vacíos y los "a revisar", con quien la usa por
// defecto; el resto lo resuelve `usar_plantilla` (catalogo.md → *El elegido
// gana sobre el fijo*). Con `hiloId` suma los pasos a ese hilo.
export function UsarPlantillaPanel({
  plantillas,
  hiloId,
  onClose,
}: {
  plantillas: PlantillaCompleta[];
  hiloId?: string;
  onClose: () => void;
}) {
  const router = useRouter();
  const { yo, asignables, pedir } = useTareas();
  const nombre = useNombre();
  const [enviando, setEnviando] = useState(false);

  function aElegir(p: PlantillaCompleta | undefined) {
    const pasos = (p?.tareas_plantillas_pasos ?? []).filter(
      (paso) =>
        (!paso.asignado_id && !paso.asignado_equipo_id) || motivoRevisar(paso, asignables, pedir) !== null
    );
    return Object.fromEntries(pasos.map((paso) => [paso.id, { asignado_id: yo, asignado_equipo_id: null }]));
  }

  const {
    register,
    handleSubmit,
    control,
    setValue,
    formState: { errors },
  } = useForm<UsarPlantillaForm>({
    resolver: zodResolver(usarPlantillaSchema),
    defaultValues: {
      plantilla_id: plantillas[0]?.id ?? "",
      titulo: "",
      hilo_id: hiloId ?? null,
      asignados: aElegir(plantillas[0]),
    },
  });
  const [plantillaId, asignados] = useWatch({ control, name: ["plantilla_id", "asignados"] });
  const plantilla = plantillas.find((p) => p.id === plantillaId);

  async function onSubmit(data: UsarPlantillaForm) {
    setEnviando(true);
    const result = await usarPlantilla(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(hiloId ? "Pasos sumados" : "Hilo creado");
    if (!hiloId) router.push(`/tareas/${result.id}`);
    onClose();
  }

  return (
    <RightPanel
      title="Usar plantilla"
      subtitle={hiloId ? "Suma sus pasos a este hilo" : "Crea un hilo con sus pasos"}
      onClose={onClose}
      footer={
        <>
          <div className="flex-1" />
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando || !plantilla}>
            {enviando ? "Guardando…" : hiloId ? "Sumar pasos" : "Crear hilo"}
          </button>
        </>
      }
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        {plantillas.length > 1 && (
          <Campo id="usar-plantilla" label="Plantilla" requerido error={errors.plantilla_id}>
            <select
              id="usar-plantilla"
              className="input"
              {...register("plantilla_id", {
                onChange: (e) => setValue("asignados", aElegir(plantillas.find((p) => p.id === e.target.value))),
              })}
            >
              {plantillas.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.nombre}
                </option>
              ))}
            </select>
          </Campo>
        )}

        {!hiloId && (
          <Campo id="usar-titulo" label="Título del hilo" error={errors.titulo}>
            <input
              id="usar-titulo"
              placeholder={plantilla?.nombre}
              className={claseInput(errors.titulo)}
              {...register("titulo")}
            />
          </Campo>
        )}

        {plantilla && (
          <div className="flex flex-col gap-3">
            <p className="t-label">Pasos</p>
            {plantilla.tareas_plantillas_pasos.map((paso, i) => {
              const elegido = asignados?.[paso.id];
              const motivo = motivoRevisar(paso, asignables, pedir);
              const fijo = paso.asignado_id ?? paso.asignado_equipo_id;
              return (
                <div key={paso.id} className="flex flex-col gap-1">
                  <p className="t-body-m font-medium">
                    {i + 1}. {paso.titulo}
                  </p>
                  {elegido ? (
                    <>
                      <AsignadoSelect
                        id={`usar-asignado-${paso.id}`}
                        value={{ asignado_id: elegido.asignado_id ?? null, asignado_equipo_id: elegido.asignado_equipo_id ?? null }}
                        onChange={(v) => setValue(`asignados.${paso.id}`, v)}
                      />
                      {motivo && (
                        <p className="t-caption text-warning-text">
                          {nombre(fijo)} {motivo === "pedido" ? "ya no es de tu equipo y no podés pedir afuera" : "ya no puede recibir"}
                        </p>
                      )}
                      {errors.asignados?.[paso.id]?.asignado_id && (
                        <p className="input-error-text">{errors.asignados[paso.id]?.asignado_id?.message}</p>
                      )}
                    </>
                  ) : (
                    <p className="t-caption">{nombre(fijo)}</p>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </form>
    </RightPanel>
  );
}
