"use client";

import { useState } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaProyecto, Usuario } from "../types";
import { TareaCard } from "./TareaCard";
import { useOrdenTemperatura } from "../useOrdenTemperatura";
import { cadenasDePasos } from "./cadenaPasos";
import { esActiva, esDeUsuario } from "./tareaFiltros";

// Misión no lee nada que la Lista no lea: mismas queries, otro recorte. Lo
// único propio es el criterio de "qué toca ahora" — lo mío, activo, no
// bloqueado por un paso previo — y mostrarlo de a uno por temperatura.
export function MisionView({
  hilos,
  tareas,
  usuarios,
  proyectos,
  miembrosPorProyecto,
  gestionarAjenas,
  puedeAsignar,
  usuarioActualId,
}: {
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  miembrosPorProyecto: Record<string, string[]>;
  gestionarAjenas: boolean;
  puedeAsignar: boolean;
  usuarioActualId: string | null;
}) {
  const [indice, setIndice] = useState(0);
  // Sin `onTemperaturaChange`: en la Lista reordenar en vivo mientras se
  // arrastra el slider es lo que se quiere, pero acá se ve una tarjeta sola y
  // el reordenamiento la cambiaría abajo del dedo. El orden se actualiza con
  // el refresh del server, después de guardar.
  const { ordenar } = useOrdenTemperatura();
  const cadenas = cadenasDePasos(tareas);

  // Posponer un hilo esconde todo lo que contiene: si el hilo espera, sus
  // tareas no son "lo que toca ahora" aunque ninguna esté pospuesta.
  const hilosPospuestos = new Set(hilos.filter((h) => h.posponer_hasta).map((h) => h.id));

  const mias = usuarioActualId
    ? tareas.filter(
        (t) =>
          esDeUsuario(t, usuarioActualId) &&
          esActiva(t) &&
          !(t.hilo_id !== null && hilosPospuestos.has(t.hilo_id))
      )
    : [];

  const bloqueadas = mias.filter((t) => cadenas.get(t.id)?.bloqueada).length;
  const cola = ordenar(mias.filter((t) => !cadenas.get(t.id)?.bloqueada));

  // El índice se recorta en vez de resetearse: al completar la tarea actual la
  // cola se acorta y la misma posición pasa a mostrar la siguiente, que es el
  // comportamiento que se espera de una vista "de a una".
  const posicion = Math.min(indice, Math.max(cola.length - 1, 0));
  const actual = cola[posicion];

  if (!actual) {
    return (
      <div className="flex flex-1 flex-col items-center justify-center gap-2 py-16 text-center">
        <p className="t-body-l">No hay nada para hacer ahora.</p>
        <p className="t-caption max-w-sm">
          {bloqueadas > 0
            ? `${bloqueadas} ${bloqueadas === 1 ? "tarea espera" : "tareas esperan"} a que se complete un paso previo.`
            : "Cuando te asignen una tarea activa, va a aparecer acá."}
        </p>
      </div>
    );
  }

  const hilo = actual.hilo_id ? hilos.find((h) => h.id === actual.hilo_id) : null;

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between gap-3">
        <p className="t-label">
          Tarea {posicion + 1} de {cola.length}
          {bloqueadas > 0 && ` · ${bloqueadas} bloqueada${bloqueadas === 1 ? "" : "s"}`}
        </p>
        <div className="flex items-center gap-2">
          <button
            className="btn btn-secondary btn-sm"
            onClick={() => setIndice(posicion - 1)}
            disabled={posicion === 0}
            aria-label="Tarea anterior"
          >
            <ChevronLeft size={16} />
          </button>
          <button
            className="btn btn-secondary btn-sm"
            onClick={() => setIndice(posicion + 1)}
            disabled={posicion >= cola.length - 1}
            aria-label="Tarea siguiente"
          >
            <ChevronRight size={16} />
          </button>
        </div>
      </div>

      <TareaCard
        key={actual.id}
        tarea={actual}
        usuarios={usuarios}
        proyectos={proyectos}
        miembrosPorProyecto={miembrosPorProyecto}
        proyectoHeredadoId={hilo?.proyecto_id ?? null}
        usuarioActualId={usuarioActualId}
        gestionarAjenas={gestionarAjenas}
        puedeAsignar={puedeAsignar}
        cadena={cadenas.get(actual.id)}
        relacionCon={usuarioActualId}
      />
    </div>
  );
}
