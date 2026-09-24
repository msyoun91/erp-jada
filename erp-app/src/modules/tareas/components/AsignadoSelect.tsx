"use client";

import { useTareas } from "./contexto";

export type AsignadoValor = { asignado_id: string | null; asignado_equipo_id: string | null };

function codificar(v: AsignadoValor) {
  if (v.asignado_id) return `u:${v.asignado_id}`;
  if (v.asignado_equipo_id) return `e:${v.asignado_equipo_id}`;
  return "";
}

function deAsignable(a: { usuario_id: string | null; equipo_id: string | null }) {
  return codificar({ asignado_id: a.usuario_id, asignado_equipo_id: a.equipo_id });
}

function decodificar(s: string): AsignadoValor {
  const [tipo, id] = s.split(":");
  return { asignado_id: tipo === "u" ? id : null, asignado_equipo_id: tipo === "e" ? id : null };
}

// Solo quien puede recibir. Lo que sería un pedido se marca, y sin
// tareas_pedir queda deshabilitado: la base lo rechazaría igual (TA010).
// `soloYo`: el asignado que no es responsable suma pasos solo para sí.
// `soloMiEquipo`: el delegador reparte dentro de su equipo, donde nada es pedido.
export function AsignadoSelect({
  id,
  value,
  onChange,
  soloYo,
  soloMiEquipo,
  vacio = "Elegí a quién",
  invalido,
}: {
  id: string;
  value: AsignadoValor;
  onChange: (v: AsignadoValor) => void;
  soloYo?: boolean;
  soloMiEquipo?: boolean;
  vacio?: string;
  invalido?: boolean;
}) {
  const { yo, asignables, pedir, nombres } = useTareas();
  const actual = codificar(value);
  const recibibles = asignables.filter((a) => a.puede_recibir && (!soloYo || a.usuario_id === yo) && (!soloMiEquipo || !a.pedido));
  const personas = recibibles.filter((a) => a.usuario_id);
  const equipos = recibibles.filter((a) => a.equipo_id);
  const fueraDeLista = actual !== "" && !recibibles.some((a) => deAsignable(a) === actual);

  function opcion(a: (typeof recibibles)[number]) {
    const valor = deAsignable(a);
    const esYo = a.usuario_id === yo;
    return (
      <option key={valor} value={valor} disabled={a.pedido && !pedir}>
        {esYo ? `${a.nombre} (yo)` : a.nombre}
        {a.pedido ? " · pedido" : ""}
      </option>
    );
  }

  return (
    <select
      id={id}
      className={`input ${invalido ? "input-error" : ""}`}
      aria-invalid={invalido}
      value={actual}
      onChange={(e) => onChange(decodificar(e.target.value))}
    >
      <option value="">{vacio}</option>
      {fueraDeLista && (
        <option value={actual} disabled>
          {nombres[value.asignado_id ?? value.asignado_equipo_id ?? ""] ?? "—"} (no puede recibir)
        </option>
      )}
      {personas.length > 0 && <optgroup label="Personas">{personas.map(opcion)}</optgroup>}
      {equipos.length > 0 && <optgroup label="Equipos">{equipos.map(opcion)}</optgroup>}
    </select>
  );
}
