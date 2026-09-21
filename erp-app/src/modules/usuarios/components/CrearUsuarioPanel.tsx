"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearUsuario } from "../actions";
import { crearUsuarioSchema, type CrearUsuarioForm } from "../types";

const FORM_ID = "crear-usuario";

export function CrearUsuarioPanel({ onClose }: { onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<CrearUsuarioForm>({ resolver: zodResolver(crearUsuarioSchema) });

  async function onSubmit(data: CrearUsuarioForm) {
    setEnviando(true);
    const result = await crearUsuario(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Usuario creado");
    onClose();
  }

  return (
    <RightPanel
      title="Nuevo usuario"
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
          {/* El submit vive en el footer del panel, fuera del <form>: los ata
              el atributo form=, sin estado ni ref de por medio. */}
          <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
            {enviando ? "Creando…" : "Crear usuario"}
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
          <label htmlFor="crear-nombre" className="t-label t-label-req mb-1 block">
            Nombre
          </label>
          <input
            id="crear-nombre"
            aria-required
            aria-invalid={!!errors.nombre}
            className={`input ${errors.nombre ? "input-error" : ""}`}
            {...register("nombre")}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div>
          <label htmlFor="crear-email" className="t-label t-label-req mb-1 block">
            Email
          </label>
          <input
            id="crear-email"
            type="email"
            aria-required
            aria-invalid={!!errors.email}
            className={`input ${errors.email ? "input-error" : ""}`}
            {...register("email")}
          />
          {errors.email && <p className="input-error-text">{errors.email.message}</p>}
        </div>

        <div>
          <label htmlFor="crear-password" className="t-label t-label-req mb-1 block">
            Contraseña
          </label>
          <input
            id="crear-password"
            type="password"
            aria-required
            aria-invalid={!!errors.password}
            className={`input ${errors.password ? "input-error" : ""}`}
            {...register("password")}
          />
          {errors.password && <p className="input-error-text">{errors.password.message}</p>}
        </div>
      </form>
    </RightPanel>
  );
}
