"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { AlertTriangle, Search } from "lucide-react";
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

  function toggle(id: string) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleVarios(ids: string[], value: boolean) {
    setSeleccionados((prev) => {
      const next = new Set(prev);
      for (const id of ids) {
        if (value) next.add(id);
        else next.delete(id);
      }
      return next;
    });
  }

  // Una función solo es alcanzable desde su vista: sin ella el permiso existe en
  // servidor pero nadie puede verlo en la UI. La server action rechaza ese estado.
  const huerfanas = useMemo(() => {
    const ids = new Set<string>();
    for (const s of submodulos) {
      if (s.tipo !== "funcion" || !s.vista_id) continue;
      if (seleccionados.has(s.id) && !seleccionados.has(s.vista_id)) ids.add(s.id);
    }
    return ids;
  }, [submodulos, seleccionados]);

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
            {huerfanas.size > 0
              ? `${huerfanas.size} función${huerfanas.size !== 1 ? "es" : ""} sin su vista autorizada`
              : cambiosPendientes > 0 &&
                `${cambiosPendientes} cambio${cambiosPendientes !== 1 ? "s" : ""} pendiente${cambiosPendientes !== 1 ? "s" : ""}`}
          </div>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={guardar}
            disabled={enviando || cambiosPendientes === 0 || huerfanas.size > 0}
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

            // El checkbox del módulo opera solo sobre lo que la búsqueda deja a la vista:
            // marcar permisos que no están en pantalla sería un cambio invisible.
            const idsVisibles = bloques.flatMap(({ vista, funciones }) => [
              vista.id,
              ...funciones.map((s) => s.id),
            ]);
            const marcados = idsVisibles.filter((id) => seleccionados.has(id)).length;
            const moduloCompleto = marcados === idsVisibles.length;

            return (
              <div key={modulo} className="border-b border-border last:border-b-0">
                <label className="flex cursor-pointer items-center gap-3 px-5 pb-1 pt-3 hover:bg-bg-subtle">
                  <input
                    type="checkbox"
                    checked={moduloCompleto}
                    ref={(el) => {
                      if (el) el.indeterminate = marcados > 0 && !moduloCompleto;
                    }}
                    onChange={(e) => toggleVarios(idsVisibles, e.target.checked)}
                    className="h-4 w-4 shrink-0 accent-brand-700"
                  />
                  <span className="t-body-m font-semibold text-text-primary">{labelModulo(modulo)}</span>
                  <span className="t-caption">
                    {marcados}/{idsVisibles.length}
                  </span>
                </label>

                {bloques.map(({ vista, funciones }) => {
                  const idsBloque = [vista.id, ...funciones.map((s) => s.id)];
                  const bloqueCompleto = idsBloque.every((id) => seleccionados.has(id));

                  return (
                  <div key={vista.id}>
                    <div className="flex items-center gap-3 py-2 pl-8 pr-5 hover:bg-bg-subtle">
                      <label className="flex min-w-0 flex-1 cursor-pointer items-center gap-3">
                        <input
                          type="checkbox"
                          checked={seleccionados.has(vista.id)}
                          onChange={() => toggle(vista.id)}
                          className="h-4 w-4 shrink-0 accent-brand-700"
                        />
                        <span className="truncate t-body-m text-text-primary">{vista.nombre}</span>
                        <span className="badge badge-info shrink-0">Vista</span>
                      </label>
                      {funciones.length > 0 && (
                        <button
                          type="button"
                          onClick={() => toggleVarios(idsBloque, !bloqueCompleto)}
                          className="shrink-0 t-caption underline-offset-2 hover:text-text-primary hover:underline"
                        >
                          {bloqueCompleto ? "Ninguna" : "Todas"}
                        </button>
                      )}
                    </div>

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
                        <span className="badge badge-neutral shrink-0">Función</span>
                        {huerfanas.has(s.id) && (
                          <AlertTriangle
                            size={14}
                            strokeWidth={1.75}
                            className="shrink-0 text-warning-text"
                            aria-label="Requiere que su vista esté autorizada"
                          />
                        )}
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
