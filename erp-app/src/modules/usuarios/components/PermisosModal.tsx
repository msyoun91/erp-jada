"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Search } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { LABEL_MAP } from "@/components/layout/SidebarNav";
import { asignarSubmodulos } from "../actions";
import type { Submodulo, Usuario } from "../types";

function labelModulo(modulo: string) {
  return LABEL_MAP[modulo] ?? modulo[0].toUpperCase() + modulo.slice(1);
}

export function PermisosModal({
  usuario,
  todos,
  submodulos,
  asignaciones,
  onClose,
}: {
  usuario: Usuario;
  todos: Usuario[];
  submodulos: Submodulo[];
  asignaciones: Record<string, string[]>;
  onClose: () => void;
}) {
  const original = useMemo(() => new Set(asignaciones[usuario.id] ?? []), [asignaciones, usuario.id]);
  const [seleccionados, setSeleccionados] = useState<Set<string>>(new Set(original));
  const [busqueda, setBusqueda] = useState("");
  const [copiarDe, setCopiarDe] = useState("");
  const [enviando, setEnviando] = useState(false);

  const porModulo = Object.groupBy(submodulos, (s) => s.modulo);

  // La vista es prerrequisito implícito de sus funciones — nunca se autoriza por
  // separado, se sincroniza sola según si esa vista puntual tiene alguna función marcada.
  function syncVista(next: Set<string>, vistaId: string) {
    const funciones = submodulos.filter((s) => s.tipo === "funcion" && s.vista_id === vistaId);
    if (funciones.length === 0) return; // vista sin funciones: se autoriza manualmente
    const tieneFuncion = funciones.some((s) => next.has(s.id));
    if (tieneFuncion) next.add(vistaId);
    else next.delete(vistaId);
  }

  function toggle(id: string) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      const item = submodulos.find((s) => s.id === id);
      if (!item) return next;
      if (next.has(id)) next.delete(id);
      else next.add(id);
      if (item.tipo === "funcion" && item.vista_id) syncVista(next, item.vista_id);
      return next;
    });
  }

  function toggleVista(vista: Submodulo, funciones: Submodulo[], value: boolean) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      if (value) next.add(vista.id);
      else next.delete(vista.id);
      for (const s of funciones) {
        if (value) next.add(s.id);
        else next.delete(s.id);
      }
      return next;
    });
  }

  function copiarPermisos() {
    if (!copiarDe) return;
    setSeleccionados(new Set(asignaciones[copiarDe] ?? []));
    setCopiarDe("");
  }

  async function guardar() {
    setEnviando(true);
    const result = await asignarSubmodulos({
      usuario_id: usuario.id,
      submodulo_ids: [...seleccionados],
    });
    setEnviando(false);

    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Permisos actualizados");
    onClose();
  }

  const cambiosPendientes = useMemo(() => {
    let count = 0;
    for (const id of new Set([...original, ...seleccionados])) {
      if (original.has(id) !== seleccionados.has(id)) count++;
    }
    return count;
  }, [original, seleccionados]);

  const otros = todos.filter((u) => u.id !== usuario.id && u.activo);

  return (
    <RightPanel
      title="Permisos"
      subtitle={usuario.nombre}
      onClose={onClose}
      footer={
        <>
          <div className="flex-1 t-caption">
            {cambiosPendientes > 0 &&
              `${cambiosPendientes} cambio${cambiosPendientes !== 1 ? "s" : ""} pendiente${cambiosPendientes !== 1 ? "s" : ""}`}
          </div>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={guardar}
            disabled={enviando || cambiosPendientes === 0}
          >
            {enviando ? "Guardando…" : "Guardar"}
          </button>
        </>
      }
    >
      {otros.length > 0 && (
          <div className="flex shrink-0 items-center gap-2 border-b border-border px-5 py-3">
            <span className="shrink-0 t-caption">Copiar de</span>
            <select
              value={copiarDe}
              onChange={(e) => setCopiarDe(e.target.value)}
              className="input flex-1 py-1.5"
            >
              <option value="">— seleccionar —</option>
              {otros.map((u) => (
                <option key={u.id} value={u.id}>
                  {u.nombre}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="btn btn-secondary btn-sm shrink-0"
              disabled={!copiarDe}
              onClick={copiarPermisos}
            >
              Copiar
            </button>
          </div>
        )}

        <div className="shrink-0 border-b border-border px-5 py-3">
          <div className="relative">
            <Search
              size={14}
              strokeWidth={1.75}
              className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-text-tertiary"
            />
            <input
              type="text"
              value={busqueda}
              onChange={(e) => setBusqueda(e.target.value)}
              placeholder="Buscar permiso…"
              className="input py-1.5 pl-8"
            />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {Object.entries(porModulo).map(([modulo, items]) => {
            if (!items) return null;
            const vistas = items.filter((s) => s.tipo === "vista").sort((a, b) => a.orden - b.orden);
            if (vistas.length === 0) return null;

            const q = busqueda.toLowerCase();
            const bloques = vistas
              .map((vista) => {
                const funciones = items.filter((s) => s.tipo === "funcion" && s.vista_id === vista.id);
                const vistaMatch = !q || vista.nombre.toLowerCase().includes(q);
                const visibles = vistaMatch ? funciones : funciones.filter((s) => s.nombre.toLowerCase().includes(q));
                if (!vistaMatch && visibles.length === 0) return null;
                return { vista, funciones: visibles };
              })
              .filter((b): b is { vista: Submodulo; funciones: Submodulo[] } => b !== null);

            if (bloques.length === 0) return null;

            return (
              <div key={modulo} className="border-b border-border last:border-b-0">
                <div className="px-5 pb-1 pt-3 t-body-m font-semibold text-text-primary">{labelModulo(modulo)}</div>

                {bloques.map(({ vista, funciones }) => {
                  const activos = funciones.filter((s) => seleccionados.has(s.id)).length;
                  const todosMarcados = funciones.length > 0 && activos === funciones.length;
                  const algunoMarcado = activos > 0 && !todosMarcados;

                  return (
                    <div key={vista.id}>
                      <label className="flex cursor-pointer items-center gap-3 py-2 pl-8 pr-5 hover:bg-bg-subtle">
                        <input
                          type="checkbox"
                          checked={funciones.length > 0 ? todosMarcados : seleccionados.has(vista.id)}
                          ref={(el) => {
                            if (el) el.indeterminate = funciones.length > 0 && algunoMarcado;
                          }}
                          onChange={(e) =>
                            funciones.length > 0
                              ? toggleVista(vista, funciones, e.target.checked)
                              : toggle(vista.id)
                          }
                          className="h-4 w-4 shrink-0 accent-brand-700"
                        />
                        <span className="t-body-m text-text-primary">{vista.nombre}</span>
                      </label>

                      {funciones.map((s) => (
                        <label
                          key={s.id}
                          className="flex cursor-pointer items-center gap-3 py-2.5 pl-14 pr-5 hover:bg-bg-subtle"
                        >
                          <input
                            type="checkbox"
                            checked={seleccionados.has(s.id)}
                            onChange={() => toggle(s.id)}
                            className="h-4 w-4 shrink-0 accent-brand-700"
                          />
                          <span className="truncate t-body-m text-text-primary">{s.nombre}</span>
                        </label>
                      ))}
                    </div>
                  );
                })}
              </div>
            );
          })}
        </div>
    </RightPanel>
  );
}
