"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, ArchiveRestore, UserPlus, ShieldCheck } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { desactivarUsuario, reactivarUsuario } from "../actions";
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
  const [texto, setTexto] = useState("");
  const [modalCrear, setModalCrear] = useState(false);
  const [usuarioPermisos, setUsuarioPermisos] = useState<Usuario | null>(null);
  const [desactivando, setDesactivando] = useState<Usuario | null>(null);

  async function onDesactivar(usuario: Usuario) {
    const result = await desactivarUsuario(usuario.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Usuario desactivado");
  }

  // Sin confirmación: reactivar no destruye nada y se deshace con "Desactivar",
  // que sí la pide.
  async function onReactivar(usuario: Usuario) {
    const result = await reactivarUsuario(usuario.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Usuario reactivado");
  }

  const q = texto.trim().toLowerCase();
  const filtrados = usuarios.filter(
    (u) => u.nombre.toLowerCase().includes(q) || u.email.toLowerCase().includes(q),
  );
  const { visibles, ...paginado } = usePaginado(filtrados);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar por nombre o email…" />
        {puedeGestionar && (
          <button className="btn btn-primary" onClick={() => setModalCrear(true)}>
            <UserPlus size={16} />
            Nuevo usuario
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="usuarios" />

      {filtrados.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin usuarios todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : 'Creá el primero con "Nuevo usuario".'}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((usuario) => (
            <div
              key={usuario.id}
              className="flex items-center gap-2 border-b border-border p-[13px] px-5 last:border-b-0"
            >
              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{usuario.nombre}</p>
                <p className="t-caption truncate">{usuario.email}</p>
              </div>

              <span className={`badge shrink-0 ${usuario.activo ? "badge-success" : "badge-neutral"}`}>
                {usuario.activo ? "Activo" : "Inactivo"}
              </span>

              {puedeGestionar && (
                <OverflowMenu
                  items={[
                    {
                      label: "Permisos",
                      icon: <ShieldCheck size={14} strokeWidth={1.75} />,
                      onClick: () => setUsuarioPermisos(usuario),
                    },
                    usuario.activo
                      ? {
                          label: "Desactivar",
                          icon: <Archive size={14} strokeWidth={1.75} />,
                          onClick: () => setDesactivando(usuario),
                          destructive: true,
                        }
                      : {
                          label: "Reactivar",
                          icon: <ArchiveRestore size={14} strokeWidth={1.75} />,
                          onClick: () => onReactivar(usuario),
                        },
                  ]}
                />
              )}
            </div>
          ))}
        </div>
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar usuario"
          mensaje={`¿Desactivar a ${desactivando.nombre}? Perderá el acceso al sistema.`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
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
    </div>
  );
}
