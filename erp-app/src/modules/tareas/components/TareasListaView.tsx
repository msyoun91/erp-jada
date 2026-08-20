"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { SearchInput } from "@/components/ui/SearchInput";
import type { TareaConAsignados, TareaHilo, TareaPlantilla, TareaProyecto, Usuario } from "../types";
import { type Relacion, relacionHilo, relacionTarea } from "../relacion";
import { HiloCard } from "./HiloCard";
import { TareaCard } from "./TareaCard";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { useOrdenTemperatura } from "../useOrdenTemperatura";

const ROLES: { valor: "" | "responsable" | "asignado"; label: string }[] = [
  { valor: "", label: "Todos" },
  { valor: "responsable", label: "Míos" },
  { valor: "asignado", label: "Involucrado" },
];

export function TareasListaView({
  hilos,
  tareas,
  usuarios,
  proyectos,
  plantillas,
  miembrosPorProyecto,
  gestionarAjenas,
  puedeAsignar,
  usuarioActualId,
}: {
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  usuarios: Usuario[];
  proyectos: TareaProyecto[];
  plantillas: TareaPlantilla[];
  miembrosPorProyecto: Record<string, string[]>;
  gestionarAjenas: boolean;
  puedeAsignar: boolean;
  usuarioActualId: string | null;
}) {
  const [texto, setTexto] = useState("");
  // Arranca filtrado en uno mismo: la vista es "lo mío" por defecto, pero el
  // panorama del equipo queda a un click (no es una restricción, es un default).
  const [asignadoId, setAsignadoId] = useState(usuarioActualId ?? "");
  // Segundo eje, independiente del anterior: el select dice de qué usuario, este
  // dice qué relación. `crearTareaSchema` obliga responsable ∈ asignados, así
  // que "responsable" y "asignado" son disjuntos.
  const [rol, setRol] = useState<"" | "responsable" | "asignado">("");
  const [creandoTarea, setCreandoTarea] = useState(false);
  const [creandoHilo, setCreandoHilo] = useState(false);
  const { ordenar, comparar, onTemperaturaChange } = useOrdenTemperatura();
  // Hilo recién creado al convertir una tarea: se abre su panel solo.
  const [hiloConvertido, setHiloConvertido] = useState<string | null>(null);

  const q = texto.trim().toLowerCase();

  function coincideTexto(titulo: string) {
    return !q || titulo.toLowerCase().includes(q);
  }

  // Los dos ejes se evalúan por separado: mezclarlos escondía el hilo cuyo
  // título matchea pero del que no sos dueño, aunque tengas un paso adentro.
  function coincideRelacion(r: Relacion) {
    if (!asignadoId) return true;
    return rol ? r === rol : r !== null;
  }

  // Sin filtro de usuario la vista no tiene perspectiva: las filas aparecen
  // porque son visibles, no por tu relación con ellas. Entonces no hay "paso
  // ajeno" que plegar ni badge de relación que explicar.
  const relacionCon = asignadoId || null;

  const tareasSueltas = tareas.filter(
    (t) =>
      t.hilo_id === null &&
      coincideTexto(t.titulo) &&
      coincideRelacion(asignadoId ? relacionTarea(t, asignadoId) : null),
  );

  const grupos = hilos.flatMap((h) => {
    const tareasDelHilo = tareas.filter((t) => t.hilo_id === h.id);
    if (!coincideRelacion(asignadoId ? relacionHilo(h, tareasDelHilo, asignadoId) : null)) return [];
    if (!coincideTexto(h.titulo) && !tareasDelHilo.some((t) => coincideTexto(t.titulo))) return [];

    // El grupo pesa lo que pesa su paso propio más caliente: así lo urgente
    // sube tenga hilo o no. Sin pasos propios (dueño del hilo sin asignación)
    // no compite por temperatura y cae al fondo.
    const propias = relacionCon
      ? tareasDelHilo.filter((t) => relacionTarea(t, relacionCon) !== null)
      : tareasDelHilo;
    return [{ hilo: h, propias: propias.length, orden: ordenar(propias)[0] ?? null }];
  });

  type Fila =
    | { tipo: "tarea"; id: string; orden: TareaConAsignados; tarea: TareaConAsignados }
    | { tipo: "hilo"; id: string; orden: TareaConAsignados | null; hilo: TareaHilo };

  const filas: Fila[] = [
    ...tareasSueltas.map((t): Fila => ({ tipo: "tarea", id: t.id, orden: t, tarea: t })),
    ...grupos.map((g): Fila => ({ tipo: "hilo", id: g.hilo.id, orden: g.orden, hilo: g.hilo })),
  ].sort((a, b) => {
    if (!a.orden || !b.orden) return (a.orden ? 0 : 1) - (b.orden ? 0 : 1);
    return comparar(a.orden, b.orden);
  });

  // La lista es de tareas: el hilo agrupa, no cuenta como ítem.
  const totalTareas = tareasSueltas.length + grupos.reduce((n, g) => n + g.propias, 0);

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
        {asignadoId && (
          <div className="flex rounded-lg border border-border p-0.5" role="group" aria-label="Filtrar por relación">
            {ROLES.map((r) => (
              <button
                key={r.valor}
                className={`t-caption rounded-md px-3 py-1 ${
                  rol === r.valor ? "bg-brand-50 font-semibold text-brand-700" : "text-text-tertiary"
                }`}
                aria-pressed={rol === r.valor}
                onClick={() => setRol(r.valor)}
              >
                {r.label}
              </button>
            ))}
          </div>
        )}
        <button className="btn btn-secondary" onClick={() => setCreandoHilo(true)}>
          <Plus size={16} />
          Nuevo hilo
        </button>
        <button className="btn btn-primary" onClick={() => setCreandoTarea(true)}>
          <Plus size={16} />
          Nueva tarea
        </button>
      </div>

      {/* ponytail: sin paginación — un solo stream de filas y grupos. Paginar si
          alguien pasa de ~50 filas visibles. */}
      <p className="t-caption mb-2">
        {totalTareas} {totalTareas === 1 ? "tarea" : "tareas"}
      </p>

      {filas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">Sin tareas todavía</p>
          <p className="t-body-m mt-1">Creá la primera con &quot;Nueva tarea&quot; o &quot;Nuevo hilo&quot;.</p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {filas.map((f) =>
            f.tipo === "hilo" ? (
              <HiloCard
                key={f.id}
                hilo={f.hilo}
                tareas={tareas}
                proyectos={proyectos}
                usuarios={usuarios}
                plantillas={plantillas}
                miembrosPorProyecto={miembrosPorProyecto}
                usuarioActualId={usuarioActualId}
                gestionarAjenas={gestionarAjenas}
                puedeAsignar={puedeAsignar}
                relacionCon={relacionCon}
                autoAbrir={hiloConvertido === f.hilo.id}
                onTemperaturaChange={onTemperaturaChange}
              />
            ) : (
              <TareaCard
                key={f.id}
                tarea={f.tarea}
                usuarios={usuarios}
                proyectos={proyectos}
                miembrosPorProyecto={miembrosPorProyecto}
                hilosDisponibles={hilos}
                usuarioActualId={usuarioActualId}
                gestionarAjenas={gestionarAjenas}
                puedeAsignar={puedeAsignar}
                relacionCon={relacionCon}
                onTemperaturaChange={onTemperaturaChange}
                onConvertida={setHiloConvertido}
              />
            ),
          )}
        </div>
      )}

      {creandoTarea && (
        <TareaFormPanel
          usuarios={usuarios}
          proyectos={proyectos}
          miembrosPorProyecto={miembrosPorProyecto}
          usuarioActualId={usuarioActualId}
          puedeAsignar={puedeAsignar}
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
