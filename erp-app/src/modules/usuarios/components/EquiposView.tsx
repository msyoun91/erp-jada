"use client";

import { useState } from "react";
import { toast } from "sonner";
import {
  Archive,
  ArchiveRestore,
  LogOut,
  Pencil,
  Plus,
  ShieldCheck,
  ShieldOff,
  SlidersHorizontal,
  UserPlus,
} from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { initials } from "@/lib/utils";
import { asignarEquipo, cambiarEstadoEquipo, designarDelegador } from "../actions";
import type { Equipo, Submodulo, Usuario } from "../types";
import { AgregarMiembroPanel } from "./AgregarMiembroPanel";
import { DelegablesPanel } from "./DelegablesPanel";
import { EquipoPanel } from "./EquipoPanel";
import { QuitarDelegadorPanel } from "./QuitarDelegadorPanel";

export function EquiposView({
  equipos,
  membresias,
  usuarios,
  submodulos,
  asignaciones,
  puedeGestionar,
}: {
  equipos: Equipo[];
  membresias: Record<string, string>;
  usuarios: Usuario[];
  submodulos: Submodulo[];
  asignaciones: Record<string, string[]>;
  puedeGestionar: boolean;
}) {
  const [editando, setEditando] = useState<Equipo | "nuevo" | null>(null);
  const [agregandoA, setAgregandoA] = useState<Equipo | null>(null);
  const [desactivando, setDesactivando] = useState<Equipo | null>(null);
  const [sacando, setSacando] = useState<{ usuario: Usuario; equipo: Equipo } | null>(null);
  const [saliente, setSaliente] = useState<Usuario | null>(null);
  const [panelDelegables, setPanelDelegables] = useState(false);

  const idDe = (codigo: string) => submodulos.find((s) => s.codigo === codigo)?.id;
  const idDelegar = idDe("usuarios_delegar");
  const idGestionar = idDe("usuarios_gestionar");
  const tiene = (usuarioId: string, submoduloId: string | undefined) =>
    !!submoduloId && (asignaciones[usuarioId]?.includes(submoduloId) ?? false);

  const miembrosDe = (equipoId: string) => usuarios.filter((u) => membresias[u.id] === equipoId);
  const nombreEquipo = (equipoId: string | undefined) =>
    equipos.find((e) => e.id === equipoId)?.nombre;

  const activos = equipos.filter((e) => e.activo);
  const desactivados = equipos.filter((e) => !e.activo);
  // Los permisos de un independiente solo los lee quien gestiona: para el
  // resto, un admin se vería como independiente.
  const independientes = puedeGestionar
    ? usuarios.filter((u) => u.activo && !membresias[u.id] && !tiene(u.id, idGestionar))
    : [];

  async function ejecutar(accion: Promise<{ success: boolean; error?: string }>, ok: string) {
    const result = await accion;
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(ok);
  }

  function itemsMiembro(usuario: Usuario, equipo: Equipo, hayDelegador: boolean) {
    if (tiene(usuario.id, idDelegar)) {
      return [
        {
          label: "Quitar delegador",
          icon: <ShieldOff size={14} strokeWidth={1.75} />,
          onClick: () => setSaliente(usuario),
        },
      ];
    }
    return [
      ...(usuario.activo && !hayDelegador
        ? [
            {
              label: "Hacer delegador",
              icon: <ShieldCheck size={14} strokeWidth={1.75} />,
              onClick: () => ejecutar(designarDelegador(usuario.id), `${usuario.nombre} es el delegador`),
            },
          ]
        : []),
      {
        label: "Sacar del equipo",
        icon: <LogOut size={14} strokeWidth={1.75} />,
        onClick: () => setSacando({ usuario, equipo }),
        destructive: true,
      },
    ];
  }

  return (
    <div>
      {puedeGestionar && (
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <button className="btn btn-primary" onClick={() => setEditando("nuevo")}>
            <Plus size={16} />
            Nuevo equipo
          </button>
          <button className="btn btn-secondary" onClick={() => setPanelDelegables(true)}>
            <SlidersHorizontal size={16} />
            Permisos delegables
          </button>
        </div>
      )}

      {activos.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin equipos todavía</p>
          <p className="t-body-m mt-1">
            {puedeGestionar
              ? 'Creá el primero con "Nuevo equipo". Cada equipo puede tener un delegador que reparte permisos entre sus miembros.'
              : "Todavía no hay equipos armados."}
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-4">
          {activos.map((equipo) => {
            const miembros = miembrosDe(equipo.id);
            const hayDelegador = miembros.some((m) => tiene(m.id, idDelegar));

            return (
              <section key={equipo.id} className="rounded-lg border border-border bg-bg-surface">
                <header className="flex items-center gap-3 border-b border-border px-5 py-3">
                  <div className="min-w-0 flex-1">
                    <h2 className="t-h3 truncate">{equipo.nombre}</h2>
                    <p className="t-caption">
                      {miembros.length === 0
                        ? "Sin miembros"
                        : `${miembros.length} miembro${miembros.length !== 1 ? "s" : ""}`}
                      {miembros.length > 0 && !hayDelegador && " · sin delegador"}
                    </p>
                  </div>
                  {puedeGestionar && (
                    <OverflowMenu
                      items={[
                        {
                          label: "Agregar miembro",
                          icon: <UserPlus size={14} strokeWidth={1.75} />,
                          onClick: () => setAgregandoA(equipo),
                        },
                        {
                          label: "Renombrar",
                          icon: <Pencil size={14} strokeWidth={1.75} />,
                          onClick: () => setEditando(equipo),
                        },
                        {
                          label: "Desactivar",
                          icon: <Archive size={14} strokeWidth={1.75} />,
                          onClick: () => setDesactivando(equipo),
                          destructive: true,
                        },
                      ]}
                    />
                  )}
                </header>

                {miembros.map((usuario) => (
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
                    {tiene(usuario.id, idDelegar) && (
                      <span className="badge badge-info shrink-0">Delegador</span>
                    )}
                    {!usuario.activo && <span className="badge badge-neutral shrink-0">Inactivo</span>}
                    {puedeGestionar && (
                      <OverflowMenu items={itemsMiembro(usuario, equipo, hayDelegador)} />
                    )}
                  </div>
                ))}
              </section>
            );
          })}
        </div>
      )}

      {independientes.length > 0 && (
        <p className="t-caption mt-4">
          Sin equipo: {independientes.map((u) => u.nombre).join(", ")}.
        </p>
      )}

      {desactivados.length > 0 && (
        <details className="mt-4">
          <summary className="t-caption cursor-pointer">
            Equipos desactivados ({desactivados.length})
          </summary>
          <div className="mt-2 flex flex-col rounded-lg border border-border bg-bg-surface">
            {desactivados.map((equipo) => (
              <div
                key={equipo.id}
                className="flex items-center gap-3 border-b border-border row last:border-b-0"
              >
                <p className="t-body-m min-w-0 flex-1 truncate text-text-primary">{equipo.nombre}</p>
                {puedeGestionar && (
                  <OverflowMenu
                    items={[
                      {
                        label: "Reactivar",
                        icon: <ArchiveRestore size={14} strokeWidth={1.75} />,
                        onClick: () => ejecutar(cambiarEstadoEquipo(equipo.id, true), "Equipo reactivado"),
                      },
                    ]}
                  />
                )}
              </div>
            ))}
          </div>
        </details>
      )}

      {editando && (
        <EquipoPanel
          equipo={editando === "nuevo" ? null : editando}
          onClose={() => setEditando(null)}
        />
      )}

      {agregandoA && (
        <AgregarMiembroPanel
          equipo={agregandoA}
          candidatos={usuarios
            .filter(
              (u) => u.activo && membresias[u.id] !== agregandoA.id && !tiene(u.id, idGestionar),
            )
            .map((usuario) => ({ usuario, equipoActual: nombreEquipo(membresias[usuario.id]) }))}
          onClose={() => setAgregandoA(null)}
        />
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar equipo"
          mensaje={`¿Desactivar ${desactivando.nombre}? Primero tiene que quedar sin miembros.`}
          onConfirm={() => ejecutar(cambiarEstadoEquipo(desactivando.id, false), "Equipo desactivado")}
          onClose={() => setDesactivando(null)}
        />
      )}

      {sacando && (
        <ConfirmModal
          title="Sacar del equipo"
          mensaje={`¿Sacar a ${sacando.usuario.nombre} de ${sacando.equipo.nombre}? Pierde lo que le dio el delegador; lo que le asignaste vos se queda.`}
          confirmLabel="Sacar"
          onConfirm={() =>
            ejecutar(
              asignarEquipo({ usuario_id: sacando.usuario.id, equipo_id: null }),
              `${sacando.usuario.nombre} quedó sin equipo`,
            )
          }
          onClose={() => setSacando(null)}
        />
      )}

      {saliente && (
        <QuitarDelegadorPanel
          saliente={saliente}
          companeros={miembrosDe(membresias[saliente.id]).filter(
            (u) => u.id !== saliente.id && u.activo,
          )}
          submodulos={submodulos}
          asignaciones={asignaciones}
          onClose={() => setSaliente(null)}
        />
      )}

      {panelDelegables && (
        <DelegablesPanel submodulos={submodulos} onClose={() => setPanelDelegables(false)} />
      )}
    </div>
  );
}
