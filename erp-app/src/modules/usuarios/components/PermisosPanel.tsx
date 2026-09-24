"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { AlertTriangle, Search } from "lucide-react";
import { RightPanel } from "@/components/ui/RightPanel";
import { LABEL_MAP } from "@/components/layout/SidebarNav";
import { asignarSubmodulos } from "../actions";
import type { Submodulo, SubmoduloRegla, Usuario } from "../types";

export function labelModulo(modulo: string) {
  return LABEL_MAP[modulo] ?? modulo[0].toUpperCase() + modulo.slice(1);
}

export function PermisosPanel({
  usuario,
  todos,
  submodulos,
  reglas,
  asignaciones,
  delegadas,
  onClose,
}: {
  usuario: Usuario;
  todos: Usuario[];
  submodulos: Submodulo[];
  reglas: SubmoduloRegla[];
  asignaciones: Record<string, string[]>;
  delegadas: Record<string, string>;
  onClose: () => void;
}) {
  const original = useMemo(() => new Set(asignaciones[usuario.id] ?? []), [asignaciones, usuario.id]);
  const [seleccionados, setSeleccionados] = useState<Set<string>>(new Set(original));
  const [tomar, setTomar] = useState<Set<string>>(new Set());
  const [busqueda, setBusqueda] = useState("");
  const [copiarDe, setCopiarDe] = useState("");
  const [enviando, setEnviando] = useState(false);

  const porModulo = Object.groupBy(submodulos, (s) => s.modulo);
  const porId = useMemo(() => new Map(submodulos.map((s) => [s.id, s])), [submodulos]);

  function etiqueta(id: string) {
    const s = porId.get(id);
    return s ? `${s.nombre} (${labelModulo(s.modulo)})` : "";
  }

  // `excluye` vale en los dos sentidos: se arma la adyacencia completa.
  const excluyentes = useMemo(() => {
    const m = new Map<string, string[]>();
    const sumar = (id: string, otro: string) => m.set(id, [...(m.get(id) ?? []), otro]);
    for (const r of reglas) {
      if (r.tipo !== "excluye" || !porId.has(r.submodulo_id) || !porId.has(r.otro_id)) continue;
      sumar(r.submodulo_id, r.otro_id);
      sumar(r.otro_id, r.submodulo_id);
    }
    return m;
  }, [reglas, porId]);

  function bloqueante(id: string, marcados: Set<string>) {
    return excluyentes.get(id)?.find((o) => marcados.has(o));
  }

  // Una función bajo una vista bloqueada queda bloqueada en cascada.
  function bloqueado(id: string, marcados: Set<string>): boolean {
    if (marcados.has(id)) return false;
    if (bloqueante(id, marcados) !== undefined) return true;
    const vista = porId.get(id)?.vista_id;
    return vista != null && bloqueado(vista, marcados);
  }

  function deshabilitado(id: string) {
    return bloqueado(id, seleccionados);
  }

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
        if (!value) next.delete(id);
        else if (!bloqueado(id, next)) next.add(id);
      }
      return next;
    });
  }

  // Espejo de `usuario_submodulos_validar` (sql/105, sql/110), que es la barrera:
  // acá solo se avisa antes de guardar. La función requiere su vista porque sin
  // ella el permiso existe en servidor pero nadie puede verlo en la UI.
  const problemas = (() => {
    const faltan = new Map<string, string[]>();
    const requiere = (id: string, otro: string) => {
      if (seleccionados.has(id) && !seleccionados.has(otro) && porId.has(otro)) {
        faltan.set(id, [...(faltan.get(id) ?? []), etiqueta(otro)]);
      }
    };
    for (const s of submodulos) if (s.tipo === "funcion" && s.vista_id) requiere(s.id, s.vista_id);
    for (const r of reglas) if (r.tipo === "requiere") requiere(r.submodulo_id, r.otro_id);

    const m = new Map<string, string>();
    for (const [id, otros] of faltan) m.set(id, `Requiere ${otros.join(", ")}`);
    for (const id of seleccionados) {
      const otro = bloqueante(id, seleccionados);
      if (otro) m.set(id, `No compatible con ${etiqueta(otro)}`);
    }
    return m;
  })();

  // Lo ya marcado con un problema avisa en amarillo; lo que no se puede marcar
  // por una exclusión dice por qué.
  function aviso(id: string) {
    const problema = problemas.get(id);
    if (problema) {
      return (
        <span className="flex min-w-0 items-center gap-1 text-warning-text" title={problema}>
          <AlertTriangle size={14} strokeWidth={1.75} className="shrink-0" aria-hidden />
          <span className="truncate t-caption text-warning-text">{problema}</span>
        </span>
      );
    }
    if (!deshabilitado(id)) return null;
    const otro = bloqueante(id, seleccionados);
    const texto = otro
      ? `No compatible con ${etiqueta(otro)}`
      : `Requiere ${etiqueta(porId.get(id)?.vista_id ?? "")}`;
    return (
      <span className="truncate t-caption" title={texto}>
        {texto}
      </span>
    );
  }

  // "Gana el admin" explícito (sql/121): guardar sin tomar deja la fila del delegador.
  function delegacion(id: string) {
    const delegador = delegadas[id];
    if (!delegador || !seleccionados.has(id)) return null;
    const tomada = tomar.has(id);
    const nombre = todos.find((u) => u.id === delegador)?.nombre ?? "el delegador";
    return (
      <span className="ml-auto flex shrink-0 items-center gap-2">
        <span className="t-caption">{tomada ? "Pasa al admin" : `Delegado por ${nombre}`}</span>
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          onClick={(e) => {
            e.preventDefault();
            setTomar((prev) => {
              const next = new Set(prev);
              if (tomada) next.delete(id);
              else next.add(id);
              return next;
            });
          }}
        >
          {tomada ? "Deshacer" : "Tomar"}
        </button>
      </span>
    );
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
      tomar_ids: [...tomar].filter((id) => seleccionados.has(id)),
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
    for (const id of tomar) if (seleccionados.has(id)) count++;
    return count;
  }, [original, seleccionados, tomar]);

  const otros = todos.filter((u) => u.id !== usuario.id && u.activo);

  return (
    <RightPanel
      title="Permisos"
      subtitle={usuario.nombre}
      onClose={onClose}
      footer={
        <>
          <div className="flex-1 t-caption">
            {problemas.size > 0
              ? `${problemas.size} permiso${problemas.size !== 1 ? "s" : ""} por resolver`
              : cambiosPendientes > 0 &&
                `${cambiosPendientes} cambio${cambiosPendientes !== 1 ? "s" : ""} pendiente${cambiosPendientes !== 1 ? "s" : ""}`}
          </div>
          <button type="button" className="btn btn-secondary btn-sm" onClick={onClose}>
            Cancelar
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={guardar}
            disabled={enviando || cambiosPendientes === 0 || problemas.size > 0}
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
              className="input flex-1"
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
              className="input pl-8"
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
            // Lo que una exclusión deja afuera no cuenta: si no, el módulo nunca queda completo.
            const moduloCompleto = idsVisibles.every((id) => seleccionados.has(id) || deshabilitado(id));

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
                  const bloqueCompleto = idsBloque.every((id) => seleccionados.has(id) || deshabilitado(id));

                  return (
                  <div key={vista.id}>
                    <div className="flex items-center gap-3 py-2 pl-8 pr-5 hover:bg-bg-subtle">
                      <label
                        className={`flex min-w-0 flex-1 items-center gap-3 ${
                          deshabilitado(vista.id) ? "cursor-not-allowed opacity-60" : "cursor-pointer"
                        }`}
                      >
                        <input
                          type="checkbox"
                          checked={seleccionados.has(vista.id)}
                          disabled={deshabilitado(vista.id)}
                          onChange={() => toggle(vista.id)}
                          className="h-4 w-4 shrink-0 accent-brand-700"
                        />
                        <span className="truncate t-body-m text-text-primary">{vista.nombre}</span>
                        <span className="badge badge-info shrink-0">Vista</span>
                        {aviso(vista.id)}
                        {delegacion(vista.id)}
                      </label>
                      {funciones.length > 0 && (
                        <button
                          type="button"
                          onClick={() => toggleVarios(idsBloque, !bloqueCompleto)}
                          className="btn btn-secondary btn-sm shrink-0"
                        >
                          {bloqueCompleto ? "Ninguna" : "Todas"}
                        </button>
                      )}
                    </div>

                    {funciones.map((s) => (
                      <label
                        key={s.id}
                        className={`flex items-center gap-3 py-2.5 pl-14 pr-5 hover:bg-bg-subtle ${
                          deshabilitado(s.id) ? "cursor-not-allowed opacity-60" : "cursor-pointer"
                        }`}
                      >
                        <input
                          type="checkbox"
                          checked={seleccionados.has(s.id)}
                          disabled={deshabilitado(s.id)}
                          onChange={() => toggle(s.id)}
                          className="h-4 w-4 shrink-0 accent-brand-700"
                        />
                        <span className="truncate t-body-m text-text-primary">{s.nombre}</span>
                        <span className="badge badge-neutral shrink-0">Función</span>
                        {aviso(s.id)}
                        {delegacion(s.id)}
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
