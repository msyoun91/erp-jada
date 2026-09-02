"use client";

import { useController, type Control, type Path } from "react-hook-form";
import { useTareasContexto } from "./tareasContexto";

// `miembros` = ids habilitados para recibir la tarea (miembros del proyecto);
// null = la tarea no tiene proyecto y cualquiera puede recibirla. El filtro es
// UX: la barrera real está en la policy de tareas_asignados.
//
// `puedeAsignar` (función `tareas_asignar`, sql/014) decide si hay picker o
// solo el resumen de a quién le queda la tarea: los valores viajan igual como
// defaults ocultos del form. El bloque de solo-lectura vive acá y no en cada
// panel para no repetirlo en TareaFormPanel y UsarPlantillaPanel.
export function AsignadosPicker<T extends { asignados: string[]; responsable_id: string }>({
  control,
  miembros,
}: {
  control: Control<T>;
  miembros: string[] | null;
}) {
  const { usuarios, puedeAsignar } = useTareasContexto();
  const asignadosField = useController({ name: "asignados" as Path<T>, control });
  const responsableField = useController({ name: "responsable_id" as Path<T>, control });

  const elegibles = miembros ? usuarios.filter((u) => miembros.includes(u.id)) : usuarios;
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

  if (!puedeAsignar) {
    const nombres = usuarios.filter((u) => seleccionados.includes(u.id)).map((u) => u.nombre);
    return (
      <div>
        <label className="t-label mb-1 block">Asignados</label>
        <p className="t-caption">
          {nombres.length > 0
            ? nombres.join(", ")
            : "Solo los miembros del proyecto pueden recibir tareas."}
        </p>
        {asignadosField.fieldState.error && (
          <p className="input-error-text">{asignadosField.fieldState.error.message}</p>
        )}
      </div>
    );
  }

  return (
    <div>
      <label className="t-label t-label-req mb-1 block">Asignados</label>
      <div className="max-h-40 overflow-y-auto rounded-md border-[1.5px] border-border-strong">
        {elegibles.length === 0 && (
          <p className="t-caption px-3 py-2">Solo los miembros del proyecto pueden recibir tareas.</p>
        )}
        {elegibles.map((u) => (
          <label
            key={u.id}
            className="tap-target flex cursor-pointer items-center gap-2 px-3 py-2 hover:bg-bg-subtle"
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

      <label className="t-label t-label-req mb-1 mt-3 block">Responsable</label>
      <select
        aria-required
        className={`input ${responsableField.fieldState.error ? "input-error" : ""}`}
        value={responsableId}
        onChange={(e) => responsableField.field.onChange(e.target.value)}
        disabled={seleccionados.length === 0}
      >
        <option value="">— seleccionar —</option>
        {elegibles
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
