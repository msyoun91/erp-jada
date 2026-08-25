"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { posponerHilo, posponerTarea } from "../actions";
import { posponerSchema, type PosponerForm } from "../types";

export function PosponerPanel({
  tipo,
  id,
  titulo,
  onClose,
}: {
  tipo: "tarea" | "hilo";
  id: string;
  titulo: string;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<PosponerForm>({
    resolver: zodResolver(posponerSchema),
    defaultValues: { id },
  });

  async function onSubmit(data: PosponerForm) {
    setEnviando(true);
    const result = tipo === "tarea" ? await posponerTarea(data) : await posponerHilo(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Pospuesto");
    onClose();
  }

  return (
    <RightPanel
      title="Posponer"
      subtitle={titulo}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button type="submit" form="form-posponer" className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : "Posponer"}
          </button>
        </>
      }
    >
      <form
        id="form-posponer"
        onSubmit={handleSubmit(onSubmit)}
        className="flex flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label className="t-label t-label-req mb-1 block">Posponer hasta</label>
          <input
            type="date"
            aria-required
            className={`input ${errors.hasta ? "input-error" : ""}`}
            {...register("hasta")}
          />
          {errors.hasta && <p className="input-error-text">{errors.hasta.message}</p>}
        </div>
      </form>
    </RightPanel>
  );
}
