"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { guardarEquipo } from "../actions";
import { equipoSchema, type Equipo, type EquipoForm } from "../types";

const FORM_ID = "equipo";

export function EquipoPanel({ equipo, onClose }: { equipo: Equipo | null; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<EquipoForm>({
    resolver: zodResolver(equipoSchema),
    defaultValues: { id: equipo?.id, nombre: equipo?.nombre ?? "" },
  });

  async function onSubmit(data: EquipoForm) {
    setEnviando(true);
    const result = await guardarEquipo(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(equipo ? "Equipo renombrado" : "Equipo creado");
    onClose();
  }

  return (
    <RightPanel
      title={equipo ? "Renombrar equipo" : "Nuevo equipo"}
      subtitle={equipo?.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={<PiePanel confirmar={equipo ? "Guardar" : "Crear equipo"} enviando={enviando} onCancelar={onClose} form={FORM_ID} />}
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label htmlFor="equipo-nombre" className="t-label t-label-req mb-1 block">
            Nombre
          </label>
          <input
            id="equipo-nombre"
            aria-required
            aria-invalid={!!errors.nombre}
            className={`input ${errors.nombre ? "input-error" : ""}`}
            {...register("nombre")}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
          {!equipo && (
            <p className="t-caption mt-1">
              Los miembros y el delegador se suman después, desde el menú del equipo.
            </p>
          )}
        </div>
      </form>
    </RightPanel>
  );
}
