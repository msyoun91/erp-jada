"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { X } from "lucide-react";
import { crearUsuario } from "../actions";
import { crearUsuarioSchema, type CrearUsuarioForm } from "../types";

export function CrearUsuarioModal({ onClose }: { onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors },
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[rgba(7,11,20,.55)] p-4">
      <div className="w-full max-w-[460px] rounded-xl bg-bg-surface p-[30px] shadow-lg">
        <div className="mb-5 flex items-center justify-between">
          <h2 className="t-h3">Nuevo usuario</h2>
          <button onClick={onClose} className="text-text-tertiary" aria-label="Cerrar">
            <X size={20} />
          </button>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
          <div>
            <label className="t-label mb-1 block">Nombre</label>
            <input
              className={`input ${errors.nombre ? "input-error" : ""}`}
              {...register("nombre")}
            />
            {errors.nombre && <p className="input-error-text">{errors.nombre.message}</p>}
          </div>

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

          <div className="mt-2 flex justify-end gap-3">
            <button type="button" className="btn btn-secondary" onClick={onClose}>
              Cancelar
            </button>
            <button type="submit" className="btn btn-primary" disabled={enviando}>
              {enviando ? "Creando..." : "Crear usuario"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
