"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Archive, ArchiveRestore, KeyRound, Pencil, UserPlus, ShieldCheck } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { initials } from "@/lib/utils";
import { desactivarUsuario, reactivarUsuario } from "../actions";
import type { Submodulo, SubmoduloRegla, Usuario } from "../types";
import { CrearUsuarioPanel } from "./CrearUsuarioPanel";
import { EditarUsuarioPanel } from "./EditarUsuarioPanel";
import { PermisosPanel } from "./PermisosPanel";
import { ResetearPasswordModal } from "./ResetearPasswordModal";

const ESTADOS = [
  { valor: "activos", label: "Activos" },
  { valor: "inactivos", label: "Inactivos" },
  { valor: "todos", label: "Todos" },
] as const;

type Estado = (typeof ESTADOS)[number]["valor"];

export function UsuariosView({
  usuarios,
  submodulos,
  reglas,
  asignaciones,
  puedeGestionar,
}: {
  usuarios: Usuario[];
  submodulos: Submodulo[];
  reglas: SubmoduloRegla[];
  asignaciones: Record<string, string[]>;
  puedeGestionar: boolean;
}) {
  const [texto, setTexto] = useState("");
  // Arranca en "activos": los desactivados son historia, no el trabajo del día.
  const [estado, setEstado] = useState<Estado>("activos");
  const [panelCrear, setPanelCrear] = useState(false);
  const [editando, setEditando] = useState<Usuario | null>(null);
  const [reseteando, setReseteando] = useState<Usuario | null>(null);
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

  function cuentaPermisos(usuarioId: string) {
    const total = asignaciones[usuarioId]?.length ?? 0;
    return total === 0 ? "Sin permisos" : `${total} permiso${total !== 1 ? "s" : ""}`;
  }

  const q = texto.trim().toLowerCase();
  const filtrados = usuarios.filter(
    (u) =>
      (estado === "todos" || (estado === "activos") === u.activo) &&
      (u.nombre.toLowerCase().includes(q) || u.email.toLowerCase().includes(q)),
  );
  const { visibles, ...paginado } = usePaginado(filtrados);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar por nombre o email…" />

        <select
          className="input w-auto"
          value={estado}
          onChange={(e) => setEstado(e.target.value as Estado)}
          aria-label="Filtrar por estado"
        >
          {ESTADOS.map((e) => (
            <option key={e.valor} value={e.valor}>
              {e.label}
            </option>
          ))}
        </select>

        {puedeGestionar && (
          <button className="btn btn-primary" onClick={() => setPanelCrear(true)}>
            <UserPlus size={16} />
            Nuevo usuario
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="usuarios" />

      {filtrados.length === 0 ? (
        <div className="empty-state">
          {/* "Sin usuarios todavía" solo si la base está vacía: con el filtro
              en "Activos" por default, una lista de puros inactivos no es una
              base vacía. */}
          <p className="t-h3">{usuarios.length === 0 ? "Sin usuarios todavía" : "Sin resultados"}</p>
          <p className="t-body-m mt-1">
            {usuarios.length === 0
              ? 'Creá el primero con "Nuevo usuario".'
              : "Probá con otro término de búsqueda o cambiá el filtro de estado."}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((usuario) => (
            <div
              key={usuario.id}
              className="flex items-center gap-3 border-b border-border row last:border-b-0"
            >
              <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-50 text-[13px] font-semibold text-text-brand">
                {initials(usuario.nombre)}
              </div>

              <div className="min-w-0 flex-1">
                <p className="t-body-m truncate font-medium text-text-primary">{usuario.nombre}</p>
                <p className="t-caption truncate">{usuario.email}</p>
              </div>

              <span className="hidden shrink-0 t-caption sm:inline">
                {cuentaPermisos(usuario.id)}
              </span>

              {/* Con el filtro en "Activos" el badge diría lo mismo en todas las
                  filas: solo aporta cuando la lista puede mezclar estados. */}
              {estado !== "activos" && (
                <span className={`badge shrink-0 ${usuario.activo ? "badge-success" : "badge-neutral"}`}>
                  {usuario.activo ? "Activo" : "Inactivo"}
                </span>
              )}

              {puedeGestionar && (
                <OverflowMenu
                  items={[
                    {
                      label: "Editar",
                      icon: <Pencil size={14} strokeWidth={1.75} />,
                      onClick: () => setEditando(usuario),
                    },
                    {
                      label: "Permisos",
                      icon: <ShieldCheck size={14} strokeWidth={1.75} />,
                      onClick: () => setUsuarioPermisos(usuario),
                    },
                    {
                      label: "Resetear contraseña",
                      icon: <KeyRound size={14} strokeWidth={1.75} />,
                      onClick: () => setReseteando(usuario),
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

      {panelCrear && <CrearUsuarioPanel onClose={() => setPanelCrear(false)} />}

      {editando && <EditarUsuarioPanel usuario={editando} onClose={() => setEditando(null)} />}

      {reseteando && (
        <ResetearPasswordModal usuario={reseteando} onClose={() => setReseteando(null)} />
      )}

      {usuarioPermisos && (
        <PermisosPanel
          usuario={usuarioPermisos}
          todos={usuarios}
          submodulos={submodulos}
          reglas={reglas}
          asignaciones={asignaciones}
          onClose={() => setUsuarioPermisos(null)}
        />
      )}
    </div>
  );
}
