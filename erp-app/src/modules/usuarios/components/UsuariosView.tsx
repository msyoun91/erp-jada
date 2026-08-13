"use client";

import { useState } from "react";
import { toast } from "sonner";
import { UserPlus, ShieldCheck } from "lucide-react";
import { ConfirmModal } from "@/components/ui/ConfirmModal";
import { desactivarUsuario } from "../actions";
import type { Submodulo, Usuario } from "../types";
import { CrearUsuarioModal } from "./CrearUsuarioModal";
import { PermisosModal } from "./PermisosModal";

export function UsuariosView({
  usuarios,
  submodulos,
  asignaciones,
  puedeGestionar,
}: {
  usuarios: Usuario[];
  submodulos: Submodulo[];
  asignaciones: Record<string, string[]>;
  puedeGestionar: boolean;
}) {
  const [modalCrear, setModalCrear] = useState(false);
  const [usuarioPermisos, setUsuarioPermisos] = useState<Usuario | null>(null);
  const [usuarioDesactivar, setUsuarioDesactivar] = useState<Usuario | null>(null);

  async function onDesactivar() {
    if (!usuarioDesactivar) return;
    const result = await desactivarUsuario(usuarioDesactivar.id);
    setUsuarioDesactivar(null);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Usuario desactivado");
  }

  return (
    <div>
      {puedeGestionar && (
        <div className="mb-4 flex justify-end">
          <button className="btn btn-primary" onClick={() => setModalCrear(true)}>
            <UserPlus size={16} />
            Nuevo usuario
          </button>
        </div>
      )}

      <p className="t-caption mb-2">{usuarios.length} usuarios</p>

      {usuarios.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin usuarios todavía</p>
          <p className="t-body-m mt-1">Creá el primero con &quot;Nuevo usuario&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {usuarios.map((usuario) => (
            <div
              key={usuario.id}
              className="flex items-center justify-between border-b border-border p-[13px] px-5 last:border-b-0"
            >
              <div>
                <p className="t-body-m font-medium text-text-primary">{usuario.nombre}</p>
                <p className="t-caption">{usuario.email}</p>
              </div>

              <div className="flex items-center gap-2">
                <span className={`badge ${usuario.activo ? "badge-success" : "badge-neutral"}`}>
                  {usuario.activo ? "Activo" : "Inactivo"}
                </span>

                {puedeGestionar && (
                  <>
                    <button
                      className="btn btn-ghost btn-sm"
                      onClick={() => setUsuarioPermisos(usuario)}
                    >
                      <ShieldCheck size={14} />
                      Permisos
                    </button>
                    {usuario.activo && (
                      <button
                        className="btn btn-ghost btn-sm text-error"
                        onClick={() => setUsuarioDesactivar(usuario)}
                      >
                        Desactivar
                      </button>
                    )}
                  </>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {modalCrear && <CrearUsuarioModal onClose={() => setModalCrear(false)} />}

      {usuarioPermisos && (
        <PermisosModal
          usuario={usuarioPermisos}
          todos={usuarios}
          submodulos={submodulos}
          asignaciones={asignaciones}
          onClose={() => setUsuarioPermisos(null)}
        />
      )}

      {usuarioDesactivar && (
        <ConfirmModal
          title="Desactivar usuario"
          message={`¿Desactivar a ${usuarioDesactivar.nombre}?`}
          confirmLabel="Desactivar"
          danger
          onConfirm={onDesactivar}
          onCancel={() => setUsuarioDesactivar(null)}
        />
      )}
    </div>
  );
}
