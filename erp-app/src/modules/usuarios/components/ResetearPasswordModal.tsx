"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Eye, EyeOff } from "lucide-react";
import { Modal } from "@/components/ui/Modal";
import { resetearPassword } from "../actions";
import { resetearPasswordSchema, type ResetearPasswordForm, type Usuario } from "../types";

export function ResetearPasswordModal({
  usuario,
  onClose,
}: {
  usuario: Usuario;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  // Visible por defecto: quien la fija se la tiene que pasar al usuario, y no
  // hay nadie mirando su propia contraseña acá.
  const [verPassword, setVerPassword] = useState(true);
  const {
    register,
    handleSubmit,
    formState: { errors, isDirty },
  } = useForm<ResetearPasswordForm>({
    resolver: zodResolver(resetearPasswordSchema),
    defaultValues: { id: usuario.id },
  });

  async function onSubmit(data: ResetearPasswordForm) {
    setEnviando(true);
    const result = await resetearPassword(data);
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Contraseña actualizada");
    onClose();
  }

  return (
    <Modal title="Resetear contraseña" onClose={onClose} maxWidth={460} hayCambios={isDirty}>
      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-4">
        <p className="t-body-m">
          Nueva contraseña para <span className="font-medium text-text-primary">{usuario.nombre}</span>.
          Pasásela por un canal seguro: no se le avisa por mail.
        </p>

        <div>
          <label htmlFor="reset-password" className="t-label t-label-req mb-1 block">
            Contraseña
          </label>
          <div className="relative">
            <input
              id="reset-password"
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

        <div className="mt-2 flex justify-end gap-3">
          <button type="button" className="btn btn-secondary" onClick={onClose} disabled={enviando}>
            Cancelar
          </button>
          <button type="submit" className="btn btn-primary" disabled={enviando}>
            {enviando ? "Guardando..." : "Guardar contraseña"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
