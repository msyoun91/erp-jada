"use client";

import { useState } from "react";
import { esHuerfano, estaAbierto } from "../derivados";
import type { HiloResumen } from "../queries";
import type { Asignable } from "../types";
import { HilosView } from "./HilosView";

type Filtro = "todos" | "huerfanos" | "desactivados" | "persona";

// Todas: el admin ve todo; el filtro "huérfanos" es desde donde transfiere
// (bajas.md → *Sin destino, queda huérfano*). `responsable` llega del aviso
// "hilos huérfanos": lo que lleva o tiene abierto esa persona.
export function TodasView({
  hilos,
  yo,
  nombres,
  asignables,
  responsable,
}: {
  hilos: HiloResumen[];
  yo: string;
  nombres: Record<string, string>;
  asignables: Asignable[];
  responsable: string | null;
}) {
  const [filtro, setFiltro] = useState<Filtro>(responsable ? "persona" : "todos");

  const filtrados = hilos.filter((h) => {
    if (filtro === "desactivados") return !h.activo;
    if (filtro === "huerfanos") return esHuerfano(h, asignables);
    if (filtro === "persona")
      return (
        h.responsable_id === responsable ||
        h.tareas.some((t) => t.activo && t.asignado_id === responsable && estaAbierto(t.estado))
      );
    return true;
  });

  return (
    <div>
      <select
        className="input mb-3 w-auto"
        value={filtro}
        onChange={(e) => setFiltro(e.target.value as Filtro)}
        aria-label="Qué hilos ver"
      >
        <option value="todos">Todos los hilos</option>
        <option value="huerfanos">Huérfanos</option>
        <option value="desactivados">Desactivados</option>
        {responsable && <option value="persona">De {nombres[responsable] ?? "—"}</option>}
      </select>
      <HilosView
        key={filtro}
        hilos={filtrados}
        yo={yo}
        nombres={nombres}
        vacio={filtro === "huerfanos" ? "Ningún hilo abierto quedó sin quien lo reciba." : "Sin hilos acá."}
      />
    </div>
  );
}
