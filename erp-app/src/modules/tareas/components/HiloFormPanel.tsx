"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearHilo, editarHilo } from "../actions";
import { hiloSchema, type Hilo, type HiloForm } from "../types";
import { Campo, claseInput } from "./Campo";

const FORM_ID = "hilo-form";

export function HiloFormPanel({ hilo, onClose }: { hilo?: Hilo; onClose: () => void }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    control,
    formState: { errors, isDirty },
  } = useForm<HiloForm>({
    resolver: zodResolver(hiloSchema),
    defaultValues: {
      id: hilo?.id,
      titulo: hilo?.titulo ?? "",
      recurrencia_cantidad: hilo?.recurrencia_cantidad ?? "",
      recurrencia_unidad: hilo?.recurrencia_unidad ?? "",
    },
  });
  const seRepite = !!useWatch({ control, name: "recurrencia_unidad" });

  async function onSubmit(data: HiloForm) {
    setEnviando(true);
    const result = hilo ? await editarHilo(data) : await crearHilo(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(hilo ? "Hilo guardado" : "Hilo creado");
    if ("id" in result) router.push(`/tareas/${result.id}`);
    onClose();
  }

  return (
    <RightPanel
      title={hilo ? "Editar hilo" : "Nuevo hilo"}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <div className="flex-1" />
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : hilo ? "Guardar" : "Crear hilo"}
          </button>
        </>
      }
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <Campo id="hilo-titulo" label="Título" requerido error={errors.titulo}>
          <input id="hilo-titulo" aria-required className={claseInput(errors.titulo)} {...register("titulo")} />
        </Campo>

        <Campo id="hilo-recurrencia" label="Se repite" error={errors.recurrencia_cantidad}>
          <div className="flex gap-2">
            {seRepite && (
              <input
                type="number"
                min={1}
                aria-label="Cada cuántos"
                className={`${claseInput(errors.recurrencia_cantidad)} w-24`}
                {...register("recurrencia_cantidad")}
              />
            )}
            <select id="hilo-recurrencia" className="input" {...register("recurrencia_unidad")}>
              <option value="">No se repite</option>
              <option value="dia">Días</option>
              <option value="mes">Meses</option>
            </select>
          </div>
          {seRepite && (
            <p className="t-caption mt-1">Al cerrarlo se crea el siguiente, con los mismos pasos sin completar.</p>
          )}
        </Campo>
      </form>
    </RightPanel>
  );
}
