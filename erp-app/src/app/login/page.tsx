"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { createClient } from "@/lib/supabase/client";

const loginSchema = z.object({
  email: z.string().min(1, "El email es obligatorio").email("Email inválido"),
  password: z.string().min(1, "La contraseña es obligatoria"),
});

type LoginForm = z.infer<typeof loginSchema>;

export default function LoginPage() {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<LoginForm>({ resolver: zodResolver(loginSchema) });

  async function onSubmit(data: LoginForm) {
    setEnviando(true);
    setError(null);

    const supabase = createClient();
    const { error: authError } = await supabase.auth.signInWithPassword(data);

    setEnviando(false);

    if (authError) {
      setError("Email o contraseña incorrectos");
      return;
    }

    router.push("/usuarios");
    router.refresh();
  }

  return (
    <div className="flex min-h-full items-center justify-center bg-bg-page p-4">
      <div className="w-full max-w-[380px] rounded-xl border border-border bg-bg-surface p-[30px] shadow-lg">
        <h1 className="t-h2 mb-6 text-center">ERP JADA</h1>

        <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
          <div>
            <label className="t-label mb-1 block">Email</label>
            <input
              type="email"
              className={`input ${errors.email ? "input-error" : ""}`}
              {...register("email")}
            />
            {errors.email && <p className="input-error-text">{errors.email.message}</p>}
          </div>

          <div>
            <label className="t-label mb-1 block">Contraseña</label>
            <input
              type="password"
              className={`input ${errors.password ? "input-error" : ""}`}
              {...register("password")}
            />
            {errors.password && (
              <p className="input-error-text">{errors.password.message}</p>
            )}
          </div>

          {error && <p className="input-error-text">{error}</p>}

          <button type="submit" className="btn btn-primary mt-2" disabled={enviando}>
            {enviando ? "Ingresando..." : "Ingresar"}
          </button>
        </form>
      </div>
    </div>
  );
}
