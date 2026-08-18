"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { agregarPasoATarea } from "../actions";
import { agregarPasoSchema, type AgregarPasoForm } from "../types";

export function AgregarPasoPanel({
  tareaId,
  titulo,
  onClose,
}: {
  tareaId: string;
  titulo: string;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<AgregarPasoForm>({
    resolver: zodResolver(agregarPasoSchema),
    defaultValues: { tarea_id: tareaId, titulo_paso: "" },
  });

  async function onSubmit(data: AgregarPasoForm) {
    setEnviando(true);
    const result = await agregarPasoATarea(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Tarea convertida en hilo");
    onClose();
  }

  return (
    <RightPanel
      title="Agregar paso"
      subtitle={titulo}
      onClose={onClose}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-agregar-paso" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : "Agregar paso"}
          </button>
        </>
      }
    >
      <form
        id="form-agregar-paso"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <p className="t-caption">
          Esta tarea pasa a ser un hilo con dos pasos: &quot;{titulo}&quot; y el que agregues acá.
        </p>
        <div>
          <label className="t-label mb-1 block">Título del paso</label>
          <input
            className={`input ${errors.titulo_paso ? "input-error" : ""}`}
            {...register("titulo_paso")}
            autoFocus
          />
          {errors.titulo_paso && <p className="input-error-text">{errors.titulo_paso.message}</p>}
        </div>
      </form>
    </RightPanel>
  );
}
