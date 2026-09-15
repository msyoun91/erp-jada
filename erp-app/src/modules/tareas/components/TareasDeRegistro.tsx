"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import type { RegistroElegido, TareaConAsignados, TareaHilo } from "../types";
import { cadenasDePasos } from "./cadenaPasos";
import { TareaCard } from "./TareaCard";
import { TareaFormPanel } from "./TareaFormPanel";
import { TareasContextoProvider, type TareasContexto } from "./tareasContexto";

// La sección "Tareas" de la ficha de una obra, empresa o persona (sql/059):
// se abre sobre la ficha, no en la Lista — a diferencia de la versión vieja
// (TareasRelacionadas, en Obras), acá se monta TareaCard con su propio panel,
// así que la ficha necesita su propio TareasContextoProvider.
export function TareasDeRegistro({
  contexto,
  registro,
  tareas,
  delHilo,
  hilos,
}: {
  contexto: TareasContexto;
  registro: RegistroElegido;
  tareas: TareaConAsignados[];
  delHilo: TareaConAsignados[];
  hilos: TareaHilo[];
}) {
  const [creando, setCreando] = useState(false);
  const cadenas = cadenasDePasos(delHilo);
  const proyectoDeHilo = new Map(hilos.map((h) => [h.id, h.proyecto_id]));

  return (
    <TareasContextoProvider valor={contexto}>
      <section>
        <div className="mb-2 flex items-center gap-2">
          <h3 className="t-h3 flex-1">Tareas</h3>
          <button className="btn btn-secondary btn-sm" onClick={() => setCreando(true)}>
            <Plus size={14} />
            Nueva tarea
          </button>
        </div>
        {tareas.length === 0 ? (
          <div className="empty-state p-8">
            <p className="t-body-m">Ninguna tarea relacionada todavía.</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {tareas.map((t) => (
              <TareaCard
                key={t.id}
                tarea={t}
                cadena={cadenas.get(t.id)}
                proyectoHeredadoId={t.hilo_id ? (proyectoDeHilo.get(t.hilo_id) ?? null) : null}
              />
            ))}
          </div>
        )}
      </section>

      {creando && <TareaFormPanel vinculosIniciales={[registro]} onClose={() => setCreando(false)} />}
    </TareasContextoProvider>
  );
}
