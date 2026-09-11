"use client";

import { useController, type Control, type FieldValues, type Path } from "react-hook-form";
import { EJECUTOR, type Usuario } from "../types";
import { SelectorUsuarios } from "./SelectorUsuarios";
import { useTareasContexto } from "./tareasContexto";

const SIN_MIEMBROS = "Solo los miembros del proyecto pueden recibir tareas.";

// `miembros` = ids habilitados para recibir la tarea (miembros del proyecto);
// null = la tarea no tiene proyecto y cualquiera puede recibirla. El filtro es
// UX: la barrera real está en la policy de tareas_asignados.
//
// `puedeAsignar` (función `tareas_asignar`, sql/014) decide si hay picker o
// solo el resumen de a quién le queda la tarea: los valores viajan igual como
// defaults ocultos del form. El bloque de solo-lectura vive acá y no en cada
// panel para no repetirlo en TareaFormPanel, ReasignarPanel y PlantillaFormPanel.
//
// Los campos se nombran por prop para poder apuntar a un paso de plantilla
// (`pasos.2.asignados`); `conEjecutor` suma "Quien la use" como un asignado más.
export function AsignadosPicker<T extends FieldValues>({
  control,
  miembros,
  campoAsignados = "asignados" as Path<T>,
  campoResponsable = "responsable_id" as Path<T>,
  conEjecutor = false,
}: {
  control: Control<T>;
  miembros: string[] | null;
  campoAsignados?: Path<T>;
  campoResponsable?: Path<T>;
  conEjecutor?: boolean;
}) {
  const { usuarios, puedeAsignar } = useTareasContexto();
  const asignadosField = useController({ name: campoAsignados, control });
  const responsableField = useController({ name: campoResponsable, control });

  const ejecutor: Usuario[] = conEjecutor ? [{ id: EJECUTOR, nombre: "Quien la use" }] : [];
  const elegibles = [...ejecutor, ...(miembros ? usuarios.filter((u) => miembros.includes(u.id)) : usuarios)];
  const nombreDe = (id: string) =>
    [...ejecutor, ...usuarios].find((u) => u.id === id)?.nombre ?? "Usuario inactivo";

  const seleccionados = (asignadosField.field.value as string[] | undefined) ?? [];
  const responsableId = (responsableField.field.value as string | undefined) ?? "";

  function cambiar(next: string[]) {
    asignadosField.field.onChange(next);
    if (!next.includes(responsableId)) {
      responsableField.field.onChange(next[0] ?? "");
    }
  }

  if (!puedeAsignar) {
    return (
      <div>
        <label className="t-label mb-1 block">Asignados</label>
        <p className="t-caption">
          {seleccionados.length > 0 ? seleccionados.map(nombreDe).join(", ") : SIN_MIEMBROS}
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
      <SelectorUsuarios
        opciones={elegibles}
        seleccionados={seleccionados}
        onChange={cambiar}
        nombreDe={nombreDe}
        sinOpciones={SIN_MIEMBROS}
      />
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
        {seleccionados.map((id) => (
          <option key={id} value={id}>
            {nombreDe(id)}
          </option>
        ))}
      </select>
      {responsableField.fieldState.error && (
        <p className="input-error-text">{responsableField.fieldState.error.message}</p>
      )}
    </div>
  );
}
