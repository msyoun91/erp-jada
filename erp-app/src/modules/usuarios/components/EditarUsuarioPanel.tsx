"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { editarUsuario } from "../actions";
import { editarUsuarioSchema, type EditarUsuarioForm, type Usuario } from "../types";

const FORM_ID = "editar-usuario";

export function EditarUsuarioPanel({
  usuario,
  onClose,
}: {
  usuario: Usuario;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<EditarUsuarioForm>({
    resolver: zodResolver(editarUsuarioSchema),
    defaultValues: { id: usuario.id, nombre: usuario.nombre, email: usuario.email },
  });

  async function onSubmit(data: EditarUsuarioForm) {
    setEnviando(true);
    const result = await editarUsuario(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Usuario actualizado");
    onClose();
  }

  return (
    <RightPanel
      title="Editar usuario"
      subtitle={usuario.nombre}
      onClose={onClose}
      hayCambios={isDirty}
      footer={
        <>
          <div className="flex-1" />
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={onClose}
            disabled={enviando}
          >
            Cancelar
          </button>
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      <form
        id={FORM_ID}
        onSubmit={handleSubmit(onSubmit)}
        className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4"
      >
        <div>
          <label htmlFor="editar-nombre" className="t-label t-label-req mb-1 block">
            Nombre
          </label>
          <input
            id="editar-nombre"
            aria-required
            aria-invalid={!!errors.nombre}
            className={`input ${errors.nombre ? "input-error" : ""}`}
            {...register("nombre")}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div>
          <label htmlFor="editar-email" className="t-label t-label-req mb-1 block">
            Email
          </label>
          <input
            id="editar-email"
            type="email"
            aria-required
            aria-invalid={!!errors.email}
            className={`input ${errors.email ? "input-error" : ""}`}
            {...register("email")}
          />
          {errors.email && <p className="input-error-text">{errors.email.message}</p>}
          <p className="t-caption mt-1">
            El email es con lo que entra al sistema: cambiarlo cambia su usuario de login.
          </p>
        </div>
      </form>
    </RightPanel>
  );
}
