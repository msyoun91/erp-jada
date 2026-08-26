"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Eye, EyeOff } from "lucide-react";
import { actualizarNombre, cambiarPassword } from "../actions";
import {
  cambiarPasswordSchema,
  perfilSchema,
  type CambiarPasswordForm,
  type PerfilForm,
} from "../types";

export function PerfilView({ nombre, email }: { nombre: string; email: string }) {
  return (
    <div className="flex max-w-lg flex-col gap-4">
      <DatosForm nombre={nombre} email={email} />
      <PasswordForm />
    </div>
  );
}

function DatosForm({ nombre, email }: { nombre: string; email: string }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isDirty },
  } = useForm<PerfilForm>({
    resolver: zodResolver(perfilSchema),
    defaultValues: { nombre },
  });

  async function onSubmit(data: PerfilForm) {
    setEnviando(true);
    const result = await actualizarNombre(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    // `reset` con lo guardado: sin esto el form queda "sucio" después de un
    // guardado exitoso y el botón sigue habilitado sin nada que guardar.
    reset(data);
    toast.success("Perfil actualizado");
  }

  return (
    <section className="rounded-lg border border-border bg-bg-surface p-5">
      <h2 className="t-h3 mb-4">Mis datos</h2>

      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
        <div>
          <label htmlFor="perfil-nombre" className="t-label t-label-req mb-1 block">
            Nombre
          </label>
          <input
            id="perfil-nombre"
            aria-invalid={!!errors.nombre}
            className={`input ${errors.nombre ? "input-error" : ""}`}
            {...register("nombre")}
          />
          {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
        </div>

        <div>
          <label htmlFor="perfil-email" className="t-label mb-1 block">
            Email
          </label>
          <input id="perfil-email" className="input" value={email} disabled readOnly />
          <p className="t-caption mt-1">
            Es tu usuario para entrar al sistema. Lo cambia un administrador desde Usuarios.
          </p>
        </div>

        <div className="flex justify-end">
          <button type="submit" className="btn btn-primary" disabled={enviando || !isDirty}>
            {enviando ? "Guardando..." : "Guardar"}
          </button>
        </div>
      </form>
    </section>
  );
}

function PasswordForm() {
  const [enviando, setEnviando] = useState(false);
  const [verPassword, setVerPassword] = useState(false);
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors },
  } = useForm<CambiarPasswordForm>({ resolver: zodResolver(cambiarPasswordSchema) });

  async function onSubmit(data: CambiarPasswordForm) {
    setEnviando(true);
    const result = await cambiarPassword(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    reset({ passwordActual: "", password: "", passwordRepetida: "" });
    toast.success("Contraseña actualizada");
  }

  return (
    <section className="rounded-lg border border-border bg-bg-surface p-5">
      <h2 className="t-h3 mb-4">Cambiar contraseña</h2>

      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
        <div>
          <label htmlFor="perfil-password-actual" className="t-label t-label-req mb-1 block">
            Contraseña actual
          </label>
          <input
            id="perfil-password-actual"
            type="password"
            autoComplete="current-password"
            aria-invalid={!!errors.passwordActual}
            className={`input ${errors.passwordActual ? "input-error" : ""}`}
            {...register("passwordActual")}
          />
          {errors.passwordActual && (
            <p className="input-error-text">{errors.passwordActual.message}</p>
          )}
        </div>

        <div>
          <label htmlFor="perfil-password" className="t-label t-label-req mb-1 block">
            Contraseña nueva
          </label>
          <div className="relative">
            <input
              id="perfil-password"
              type={verPassword ? "text" : "password"}
              autoComplete="new-password"
              aria-invalid={!!errors.password}
              className={`input pr-12 ${errors.password ? "input-error" : ""}`}
              {...register("password")}
            />
            <button
              type="button"
              onClick={() => setVerPassword((v) => !v)}
              aria-label={verPassword ? "Ocultar contraseña" : "Mostrar contraseña"}
              aria-pressed={verPassword}
              className="icon-btn absolute right-1 top-1/2 -translate-y-1/2 text-text-tertiary"
            >
              {verPassword ? <EyeOff size={18} strokeWidth={1.75} /> : <Eye size={18} strokeWidth={1.75} />}
            </button>
          </div>
          {errors.password && <p className="input-error-text">{errors.password.message}</p>}
        </div>

        <div>
          <label htmlFor="perfil-password-repetida" className="t-label t-label-req mb-1 block">
            Repetir contraseña nueva
          </label>
          <input
            id="perfil-password-repetida"
            type={verPassword ? "text" : "password"}
            autoComplete="new-password"
            aria-invalid={!!errors.passwordRepetida}
            className={`input ${errors.passwordRepetida ? "input-error" : ""}`}
            {...register("passwordRepetida")}
          />
          {errors.passwordRepetida && (
            <p className="input-error-text">{errors.passwordRepetida.message}</p>
          )}
        </div>

        <div className="flex justify-end">
          <button type="submit" className="btn btn-primary" disabled={enviando}>
            {enviando ? "Guardando..." : "Cambiar contraseña"}
          </button>
        </div>
      </form>
    </section>
  );
}
