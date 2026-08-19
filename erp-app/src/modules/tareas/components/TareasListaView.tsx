"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { HiloCard } from "./HiloCard";
import { TareaCard } from "./TareaCard";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { useOrdenTemperatura } from "../useOrdenTemperatura";

// "Involucrado", no solo asignado: el filtro de la toolbar arranca en el
// usuario actual y esconderle lo que creó o de lo que es responsable —
// porque no se auto-asignó — lo dejaría sin ver tareas propias.
function estaInvolucrado(t: TareaConAsignados, usuarioId: string) {
  return (
    t.creado_por === usuarioId ||
    t.responsable_id === usuarioId ||
    t.tareas_asignados.some((a) => a.activo && a.usuario_id === usuarioId)
  );
}

export function TareasListaView({
  hilos,
  tareas,
  usuarios,
  proyectos,
  plantillas,
  miembrosPorProyecto,
  gestionarAjenas,
  usuarioActualId,
}: {
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  plantillas: TareaPlantilla[];
  miembrosPorProyecto: Record<string, string[]>;
  gestionarAjenas: boolean;
  usuarioActualId: string | null;
}) {
  const [texto, setTexto] = useState("");
  // Arranca filtrado en uno mismo: la vista es "lo mío" por defecto, pero el
  // panorama del equipo queda a un click (no es una restricción, es un default).
  const [asignadoId, setAsignadoId] = useState(usuarioActualId ?? "");
  const [creandoTarea, setCreandoTarea] = useState(false);
  const [creandoHilo, setCreandoHilo] = useState(false);
  const { ordenar, onTemperaturaChange } = useOrdenTemperatura();
  // Hilo recién creado al convertir una tarea: se abre su panel solo.
  const [hiloConvertido, setHiloConvertido] = useState<string | null>(null);

  function coincide(t: TareaConAsignados) {
    const q = texto.trim().toLowerCase();
    if (q && !t.titulo.toLowerCase().includes(q)) return false;
    if (asignadoId && !estaInvolucrado(t, asignadoId)) return false;
    return true;
  }

  const tareasSueltas = ordenar(tareas.filter((t) => t.hilo_id === null && coincide(t)));

  const hayFiltro = texto.trim() !== "" || asignadoId !== "";

  // Un hilo entra si coincide él mismo (título + involucrado) o si alguna de
  // sus tareas coincide — filtrar por usuario no debe esconder el hilo que
  // contiene sus tareas.
  const hilosFiltrados = !hayFiltro
    ? hilos
    : hilos.filter((h) => {
        const q = texto.trim().toLowerCase();
        const hiloMatch =
          (!q || h.titulo.toLowerCase().includes(q)) &&
          (!asignadoId || h.creado_por === asignadoId || h.responsable_id === asignadoId);
        const tareasDelHilo = tareas.filter((t) => t.hilo_id === h.id);
        return hiloMatch || tareasDelHilo.some(coincide);
      });

  const sinResultados = hilosFiltrados.length === 0 && tareasSueltas.length === 0;

  // Sin tareas_gestionar_ajenas el filtro no ofrece la lista del equipo: solo
  // "yo" y "Todos los usuarios" (lo propio + lo público, que es todo lo que
  // RLS devuelve). No es una barrera — recortar por otro usuario nunca mostró
  // de más — sino no ofrecer un recorte que no es de quien mira.
  const opcionesUsuario = gestionarAjenas ? usuarios : usuarios.filter((u) => u.id === usuarioActualId);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar tarea o hilo…" />
        <select
          className="input w-auto py-1.5"
          value={asignadoId}
          onChange={(e) => setAsignadoId(e.target.value)}
          aria-label="Filtrar por usuario"
        >
          <option value="">Todos los usuarios</option>
          {opcionesUsuario.map((u) => (
            <option key={u.id} value={u.id}>
              {u.nombre}
            </option>
          ))}
        </select>
        <button className="btn btn-secondary" onClick={() => setCreandoHilo(true)}>
          <Plus size={16} />
          Nuevo hilo
        </button>
        <button className="btn btn-primary" onClick={() => setCreandoTarea(true)}>
          <Plus size={16} />
          Nueva tarea
        </button>
      </div>

      {/* ponytail: sin paginación — la vista agrupa hilos (cards con tareas anidadas) y tareas sueltas;
          paginar la concatenación de los dos grupos confunde. Paginar por grupo si alguien pasa de ~20 hilos. */}
      <p className="t-caption mb-2">
        {hilosFiltrados.length} hilos · {tareasSueltas.length} tareas sueltas
      </p>

      {sinResultados ? (
        <div className="empty-state">
          <p className="t-h3">Sin tareas todavía</p>
          <p className="t-body-m mt-1">Creá la primera con &quot;Nueva tarea&quot; o &quot;Nuevo hilo&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-6">
          {hilosFiltrados.length > 0 && (
            <div className="flex flex-col gap-3">
              <p className="t-label text-text-tertiary">Hilos</p>
              {hilosFiltrados.map((h) => (
                <HiloCard
                  key={h.id}
                  hilo={h}
                  tareas={tareas}
                  proyectos={proyectos}
                  usuarios={usuarios}
                  plantillas={plantillas}
                  miembrosPorProyecto={miembrosPorProyecto}
                  usuarioActualId={usuarioActualId}
                  gestionarAjenas={gestionarAjenas}
                  relacionCon={asignadoId || usuarioActualId}
                  autoAbrir={hiloConvertido === h.id}
                />
              ))}
            </div>
          )}

          {tareasSueltas.length > 0 && (
            <div className="flex flex-col gap-3">
              <p className="t-label text-text-tertiary">Tareas sueltas</p>
              {tareasSueltas.map((t) => (
                <TareaCard
                  key={t.id}
                  tarea={t}
                  usuarios={usuarios}
                  proyectos={proyectos}
                  miembrosPorProyecto={miembrosPorProyecto}
                  hilosDisponibles={hilos}
                  usuarioActualId={usuarioActualId}
                  gestionarAjenas={gestionarAjenas}
                  relacionCon={asignadoId || usuarioActualId}
                  onTemperaturaChange={onTemperaturaChange}
                  onConvertida={setHiloConvertido}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {creandoTarea && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          onClose={() => setCreandoTarea(false)}
        />
      )}
      {creandoHilo && (
        <HiloFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          usuarioActualId={usuarioActualId}
          onClose={() => setCreandoHilo(false)}
        />
      )}
    </div>
  );
}
