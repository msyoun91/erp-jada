"use client";

import { useEffect, useState } from "react";
import { ChevronDown, ChevronLeft, ChevronRight, ChevronUp, CircleCheck, Lock } from "lucide-react";
import type { TareaConAsignados, TareaHilo, TareaProyecto, Usuario } from "../types";
import { TareaCard } from "./TareaCard";
import { useOrdenTemperatura } from "../useOrdenTemperatura";
import { cadenasDePasos, type PasoEnCadena } from "./cadenaPasos";
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

  const bloqueadas = mias.filter((t) => cadenas.get(t.id)?.bloqueada);
  const cola = ordenar(mias.filter((t) => !cadenas.get(t.id)?.bloqueada));
  const total = cola.length;

  // Recorrer la cola con las flechas: la vista existe para pasar tarea por
  // tarea sin soltar el teclado. El clamp usa `total` y no el `posicion` del
  // render, para que apretar de más al final no deje el índice colgado lejos.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      // Con un panel o modal abierto las flechas son suyas (campos del form) —
      // vive en el top layer, no en este árbol.
      if (document.querySelector("dialog[open]")) return;
      const destino = e.target as HTMLElement | null;
      if (destino && ["INPUT", "SELECT", "TEXTAREA"].includes(destino.tagName)) return;
      setIndice((i) =>
        Math.min(Math.max(i + (e.key === "ArrowLeft" ? -1 : 1), 0), Math.max(total - 1, 0))
      );
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [total]);

  // El índice se recorta en vez de resetearse: al completar la tarea actual la
  // cola se acorta y la misma posición pasa a mostrar la siguiente, que es el
  // comportamiento que se espera de una vista "de a una".
  const posicion = Math.min(indice, Math.max(total - 1, 0));
  const actual = cola[posicion];

  if (!actual) {
    return (
      <div className="mx-auto flex w-full max-w-2xl flex-col gap-3">
        <div className="empty-state">
          {bloqueadas.length > 0 ? (
            <Lock size={30} strokeWidth={1.5} className="mx-auto mb-3 text-warning" />
          ) : (
            <CircleCheck size={30} strokeWidth={1.5} className="mx-auto mb-3 text-success" />
          )}
          <p className="t-h3">No hay nada para hacer ahora.</p>
          <p className="t-body-m mt-1">
            {bloqueadas.length > 0
              ? "Todo lo tuyo espera a que se complete un paso previo."
              : "Cuando te asignen una tarea activa, va a aparecer acá."}
          </p>
        </div>
        <Bloqueadas tareas={bloqueadas} cadenas={cadenas} />
      </div>
    );
  }

  const hilo = actual.hilo_id ? hilos.find((h) => h.id === actual.hilo_id) : null;
  // El proyecto de una tarea con hilo lo pone el hilo — la tarea no lo guarda
  // (CHECK `hilo_id IS NULL OR proyecto_id IS NULL`).
  const proyectoId = hilo ? hilo.proyecto_id : actual.proyecto_id;
  const proyecto = proyectoId ? proyectos.find((p) => p.id === proyectoId) : null;
  // Dónde vive la tarea: ni la isla ni su meta lo dicen, y con una sola tarjeta
  // en pantalla es lo primero que se pierde de vista.
  const contexto = [proyecto?.nombre, hilo?.titulo].filter(Boolean).join(" · ");
  const siguiente = cola[posicion + 1];

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-4">
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between gap-3">
          <p className="t-label">
            Tarea {posicion + 1} de {total}
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
              disabled={posicion >= total - 1}
              aria-label="Tarea siguiente"
            >
              <ChevronRight size={16} />
            </button>
          </div>
        </div>
        <div className="h-1 w-full overflow-hidden rounded-full bg-bg-subtle">
          <div
            className="h-full rounded-full bg-brand-500 transition-[width]"
            style={{ width: `${((posicion + 1) / total) * 100}%` }}
          />
        </div>
      </div>

      <div className="flex flex-col gap-2">
        {contexto && <p className="t-caption truncate">{contexto}</p>}

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

        {/* Texto plano de solo lectura, no una segunda cara de la tarjeta: una
            vista de a una que obliga a abrir el panel para leer qué hay que
            hacer no es una vista de a una. */}
        {actual.descripcion && (
          <p className="t-body-m whitespace-pre-line rounded-lg bg-bg-subtle px-5 py-4">
            {actual.descripcion}
          </p>
        )}
      </div>

      {siguiente && (
        <p className="t-caption truncate">
          Sigue: <span className="text-text-secondary">{siguiente.titulo}</span>
        </p>
      )}

      <Bloqueadas tareas={bloqueadas} cadenas={cadenas} />
    </div>
  );
}

// Una cola vacía con trabajo bloqueado detrás se lee como una vista rota: el
// contador solo no alcanza, hay que poder ver qué está frenando qué.
function Bloqueadas({
  tareas,
  cadenas,
}: {
  tareas: TareaConAsignados[];
  cadenas: Map<string, PasoEnCadena>;
}) {
  const [abierto, setAbierto] = useState(false);

  if (tareas.length === 0) return null;

  return (
    <div className="flex flex-col gap-2">
      <button className="btn btn-ghost btn-sm self-start" onClick={() => setAbierto(!abierto)}>
        <Lock size={14} strokeWidth={1.75} />
        {tareas.length} {tareas.length === 1 ? "tarea espera" : "tareas esperan"} un paso previo
        {abierto ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
      </button>

      {abierto && (
        <ul className="flex flex-col gap-3 rounded-lg border border-border bg-bg-surface px-5 py-4">
          {tareas.map((t) => {
            const info = cadenas.get(t.id);
            const previa = info ? info.cadena[info.posicion - 2] : undefined;
            return (
              <li key={t.id} className="flex flex-col">
                <span className="t-body-m font-semibold text-text-primary">{t.titulo}</span>
                <span className="t-caption">
                  {previa ? `Espera a «${previa.titulo}»` : "Espera un paso previo"}
                </span>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
