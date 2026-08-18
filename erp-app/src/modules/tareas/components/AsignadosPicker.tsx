"use client";

import { useController, type Control, type Path } from "react-hook-form";
import type { Usuario } from "../types";

export function AsignadosPicker<T extends { asignados: string[]; responsable_id: string }>({
  control,
  usuarios,
}: {
  control: Control<T>;
  usuarios: Usuario[];
}) {
  const asignadosField = useController({ name: "asignados" as Path<T>, control });
  const responsableField = useController({ name: "responsable_id" as Path<T>, control });

  const seleccionados = (asignadosField.field.value as string[] | undefined) ?? [];
  const responsableId = (responsableField.field.value as string | undefined) ?? "";

  function toggle(id: string) {
    const next = seleccionados.includes(id)
      ? seleccionados.filter((x) => x !== id)
      : [...seleccionados, id];
    asignadosField.field.onChange(next);
    if (!next.includes(responsableId)) {
      responsableField.field.onChange(next[0] ?? "");
    }
  }

  return (
    <div>
      <label className="t-label mb-1 block">Asignados</label>
      <div className="max-h-40 overflow-y-auto rounded-md border-[1.5px] border-border-strong">
        {usuarios.map((u) => (
          <label
            key={u.id}
            className="flex cursor-pointer items-center gap-2 px-3 py-2 hover:bg-bg-subtle"
          >
            <input
              type="checkbox"
              checked={seleccionados.includes(u.id)}
              onChange={() => toggle(u.id)}
              className="h-4 w-4 shrink-0 accent-brand-700"
            />
            <span className="t-body-m">{u.nombre}</span>
          </label>
        ))}
      </div>
      {asignadosField.fieldState.error && (
        <p className="input-error-text">{asignadosField.fieldState.error.message}</p>
      )}

      <label className="t-label mb-1 mt-3 block">Responsable</label>
      <select
        className={`input ${responsableField.fieldState.error ? "input-error" : ""}`}
        value={responsableId}
        onChange={(e) => responsableField.field.onChange(e.target.value)}
        disabled={seleccionados.length === 0}
      >
        <option value="">— seleccionar —</option>
        {usuarios
          .filter((u) => seleccionados.includes(u.id))
          .map((u) => (
            <option key={u.id} value={u.id}>
              {u.nombre}
            </option>
          ))}
      </select>
      {responsableField.fieldState.error && (
        <p className="input-error-text">{responsableField.fieldState.error.message}</p>
      )}
    </div>
  );
}
