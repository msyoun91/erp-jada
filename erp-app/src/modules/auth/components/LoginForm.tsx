"use client";

import { useState } from "react";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Eye, EyeOff } from "lucide-react";
import { signInAction } from "../actions";
import { loginSchema, type LoginForm as LoginFormValues } from "../types";

// El proxy corta la sesión de un usuario desactivado y manda el motivo por
// query: sin esto la pantalla de login no explica por qué lo echó.
const MENSAJES_MOTIVO: Record<string, string> = {
  inactivo: "Tu cuenta fue desactivada. Contactá a un administrador.",
};

export function LoginForm({ next, motivo }: { next?: string; motivo?: string }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [verPassword, setVerPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const aviso = motivo ? MENSAJES_MOTIVO[motivo] : undefined;
  const {
    register,
    handleSubmit,
    setFocus,
    formState: { errors },
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { next },
  });

  async function onSubmit(data: LoginFormValues) {
    setEnviando(true);
    setError(null);

    let resultado;
    try {
      resultado = await signInAction(data);
    } catch {
      // La action ya devuelve los errores de Supabase como valor: si el await
      // tira, no llegó al servidor.
      setError("Sin conexión. Revisá la red e intentá de nuevo.");
      setEnviando(false);
      return;
    }

    if (!resultado.success) {
      setError(resultado.error);
      setEnviando(false);
      setFocus("password");
      return;
    }

    // `enviando` queda en true a propósito: el botón sigue deshabilitado hasta
    // que la navegación ocurre, si no se puede disparar un segundo login.
    router.replace(resultado.destino);
    router.refresh();
  }

  return (
    // pb-20 reserva el rincón del ThemeToggle (fixed bottom-4, 56px): en un
    // viewport bajo el card centrado le quedaba encima del botón Ingresar.
    <div className="flex min-h-dvh items-center justify-center bg-bg-page p-4 pb-20">
      <div className="w-full max-w-sm overflow-hidden rounded-xl border border-border bg-bg-surface shadow-md">
        <div className="h-1 bg-gradient-brand" />

        <div className="p-8">
          <div className="mb-6 flex flex-col items-center gap-2">
            {/* El logotipo es el encabezado visual; el `h1` existe para que la
                pantalla tenga un heading que anunciar. */}
            <h1 className="sr-only">Ingresar a ERP JADA</h1>
            <Image src="/logo.svg" alt="JADA" width={128} height={47} className="logo" priority />
            <p className="t-body-m">Ingresá con tu cuenta</p>
          </div>

          {/* Se oculta apenas hay un error del servidor: el veredicto del
              intento actual manda sobre el motivo del corte anterior. */}
          {aviso && !error && (
            <p
              role="status"
              className="mb-4 rounded-md border border-warning/20 bg-warning-bg px-3 py-2 text-sm text-warning-text"
            >
              {aviso}
            </p>
          )}

          {/* `onInvalid` limpia el error del servidor: `onSubmit` no corre si
              falla el resolver, y sin esto el fallo de credenciales anterior
              queda en pantalla junto al error de campo nuevo — un veredicto
              sobre un request que nunca salió del browser. */}
          {/* `method="post"` no lo usa el camino normal — lo usa el submit
              nativo de antes de hidratar. Sin esto el default es GET y el
              browser serializa la contraseña en la query string, donde queda
              en el historial y en los logs del servidor. */}
          <form
            method="post"
            noValidate
            onSubmit={handleSubmit(onSubmit, () => setError(null))}
            className="flex flex-col gap-4"
          >
            <input type="hidden" {...register("next")} />

            <div>
              <label htmlFor="email" className="t-label t-label-req mb-1 block">
                Email
              </label>
              <input
                id="email"
                type="email"
                autoFocus
                autoComplete="email"
                aria-required
                aria-invalid={!!errors.email}
                aria-describedby={errors.email ? "email-error" : undefined}
                className={`input ${errors.email ? "input-error" : ""}`}
                {...register("email")}
              />
              {errors.email && (
                <p id="email-error" className="input-error-text">
                  {errors.email.message}
                </p>
              )}
            </div>

            <div>
              <label htmlFor="password" className="t-label t-label-req mb-1 block">
                Contraseña
              </label>
              <div className="relative">
                <input
                  id="password"
                  type={verPassword ? "text" : "password"}
                  autoComplete="current-password"
                  aria-required
                  aria-invalid={!!errors.password}
                  aria-describedby={errors.password ? "password-error" : undefined}
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
              {errors.password && (
                <p id="password-error" className="input-error-text">
                  {errors.password.message}
                </p>
              )}
            </div>

            {/* Bloque, no `input-error-text`: el fallo de credenciales es el
                mensaje más importante de la pantalla, no un error de campo. */}
            {error && (
              <p
                role="alert"
                className="rounded-md border border-error/20 bg-error-bg px-3 py-2 text-sm text-error-text"
              >
                {error}
              </p>
            )}

            <button type="submit" className="btn btn-primary mt-2 justify-center" disabled={enviando}>
              {enviando && (
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white/30 border-t-white" />
              )}
              {enviando ? "Ingresando..." : "Ingresar"}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
}
