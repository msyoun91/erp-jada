"use client";

import { useState } from "react";
import { Plus } from "lucide-react";
import { Paginacion } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import type { TareaConAsignados, TareaHilo, TareaPlantilla } from "../types";
import { type Relacion, relacionHilo, relacionTarea } from "../relacion";
import { HiloCard } from "./HiloCard";
import { TareaCard } from "./TareaCard";
import { TareaFormPanel } from "./TareaFormPanel";
import { HiloFormPanel } from "./HiloFormPanel";
import { useOrdenTemperatura } from "../useOrdenTemperatura";
import { esTerminada } from "./tareaFiltros";
import { useTareasContexto } from "./tareasContexto";

const ROLES: { valor: "" | "responsable" | "asignado"; label: string }[] = [
  { valor: "", label: "Todos" },
  { valor: "responsable", label: "Míos" },
  { valor: "asignado", label: "Involucrado" },
];

export function TareasListaView({
  hilos,
  tareas,
  plantillas,
}: {
  hilos: TareaHilo[];
  tareas: TareaConAsignados[];
  plantillas: TareaPlantilla[];
}) {
  const { usuarios, usuarioActualId, gestionarAjenas } = useTareasContexto();
  const [texto, setTexto] = useState("");
  // Arranca filtrado en uno mismo: la vista es "lo mío" por defecto, pero el
  // panorama del equipo queda a un click (no es una restricción, es un default).
  const [asignadoId, setAsignadoId] = useState(usuarioActualId ?? "");
  // Segundo eje, independiente del anterior: el select dice de qué usuario, este
  // dice qué relación. `crearTareaSchema` obliga responsable ∈ asignados, así
  // que "responsable" y "asignado" son disjuntos.
  const [rol, setRol] = useState<"" | "responsable" | "asignado">("");
  // Lo terminado se acumula para siempre: la Lista arranca mostrando trabajo,
  // no historial. Adentro de un hilo no se filtra nada — los pasos hechos son
  // el contexto que explica en qué anda la cadena.
  const [ocultarTerminadas, setOcultarTerminadas] = useState(true);
  const [creandoTarea, setCreandoTarea] = useState(false);
  const [creandoHilo, setCreandoHilo] = useState(false);
  const { ordenar, comparar, onTemperaturaChange } = useOrdenTemperatura();
  // Hilo recién creado al convertir una tarea: se abre su panel solo.
  const [hiloConvertido, setHiloConvertido] = useState<string | null>(null);

  const q = texto.trim().toLowerCase();

  function coincideTexto(...textos: (string | null)[]) {
    return !q || textos.some((t) => t?.toLowerCase().includes(q));
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
      coincideTexto(t.titulo, t.descripcion) &&
      coincideRelacion(asignadoId ? relacionTarea(t, asignadoId) : null),
  );

  const grupos = hilos.flatMap((h) => {
    const tareasDelHilo = tareas.filter((t) => t.hilo_id === h.id);
    if (!coincideRelacion(asignadoId ? relacionHilo(h, tareasDelHilo, asignadoId) : null)) return [];
    if (
      !coincideTexto(h.titulo, h.descripcion) &&
      !tareasDelHilo.some((t) => coincideTexto(t.titulo, t.descripcion))
    )
      return [];

    // El grupo pesa lo que pesa su paso propio más caliente: así lo urgente
    // sube tenga hilo o no. Sin pasos propios (dueño del hilo sin asignación)
    // no compite por temperatura y cae al fondo.
    const propias = relacionCon
      ? tareasDelHilo.filter((t) => relacionTarea(t, relacionCon) !== null)
      : tareasDelHilo;
    // Un hilo cerrado, o con todos sus pasos terminados, es historial: se
    // esconde entero. Un hilo vacío todavía es trabajo por empezar.
    const terminado =
      h.estado === "cerrado" || (tareasDelHilo.length > 0 && tareasDelHilo.every(esTerminada));
    return [{ hilo: h, propias: propias.length, orden: ordenar(propias)[0] ?? null, terminado }];
  });

  const sueltasVisibles = ocultarTerminadas ? tareasSueltas.filter((t) => !esTerminada(t)) : tareasSueltas;
  const gruposVisibles = ocultarTerminadas ? grupos.filter((g) => !g.terminado) : grupos;
  const ocultas = tareasSueltas.length - sueltasVisibles.length + (grupos.length - gruposVisibles.length);

  type Fila =
    | { tipo: "tarea"; id: string; orden: TareaConAsignados; tarea: TareaConAsignados }
    | { tipo: "hilo"; id: string; orden: TareaConAsignados | null; hilo: TareaHilo };

  const filas: Fila[] = [
    ...sueltasVisibles.map((t): Fila => ({ tipo: "tarea", id: t.id, orden: t, tarea: t })),
    ...gruposVisibles.map((g): Fila => ({ tipo: "hilo", id: g.hilo.id, orden: g.orden, hilo: g.hilo })),
  ].sort((a, b) => {
    if (!a.orden || !b.orden) return (a.orden ? 0 : 1) - (b.orden ? 0 : 1);
    return comparar(a.orden, b.orden);
  });

  // La lista es de tareas: el hilo agrupa, no cuenta como ítem.
  const totalTareas = sueltasVisibles.length + gruposVisibles.reduce((n, g) => n + g.propias, 0);
  const hayFiltro = Boolean(texto || asignadoId || ocultas);

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
          data-tour="tareas_lista_usuario"
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
          <div
            data-tour="tareas_lista_relacion"
            className="flex rounded-lg border border-border p-0.5"
            role="group"
            aria-label="Filtrar por relación"
          >
            {ROLES.map((r) => (
              <button
                key={r.valor}
                className={`tap-target t-caption rounded-md px-3 py-1 ${
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
        <button
          type="button"
          data-tour="tareas_lista_terminadas"
          aria-pressed={ocultarTerminadas}
          className={`tap-target t-caption rounded-lg border px-3 py-1 ${
            ocultarTerminadas
              ? "border-brand-500 bg-brand-50 font-semibold text-brand-700"
              : "border-border text-text-tertiary"
          }`}
          onClick={() => setOcultarTerminadas(!ocultarTerminadas)}
        >
          Ocultar terminadas
        </button>
        <button
          data-tour="tareas_lista_hilo"
          className="btn btn-secondary"
          onClick={() => setCreandoHilo(true)}
        >
          <Plus size={16} />
          Nuevo hilo
        </button>
        <button
          data-tour="tareas_lista_tarea"
          className="btn btn-primary"
          onClick={() => setCreandoTarea(true)}
        >
          <Plus size={16} />
          Nueva tarea
        </button>
      </div>

      {/* ponytail: sin paginación — un solo stream de filas y grupos. Paginar si
          alguien pasa de ~50 filas visibles. El contador igual sale de
          `Paginacion`, como en Proyectos, Plantillas y Auditoría. */}
      <Paginacion total={totalTareas} etiqueta="tareas" />

      {filas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{hayFiltro ? "Sin resultados" : "Sin tareas todavía"}</p>
          <p className="t-body-m mt-1">
            {!hayFiltro
              ? 'Creá la primera con "Nueva tarea" o "Nuevo hilo".'
              : ocultas > 0
                ? `Hay ${ocultas} ${ocultas === 1 ? "fila terminada" : "filas terminadas"} escondidas — mostralas con "Ocultar terminadas".`
                : "Probá con otro término de búsqueda o con otro usuario."}
          </p>
        </div>
      ) : (
        <div data-tour="tareas_lista_isla" className="flex flex-col gap-3">
          {filas.map((f) =>
            f.tipo === "hilo" ? (
              <HiloCard
                key={f.id}
                hilo={f.hilo}
                tareas={tareas}
                plantillas={plantillas}
                relacionCon={relacionCon}
                autoAbrir={hiloConvertido === f.hilo.id}
                onTemperaturaChange={onTemperaturaChange}
              />
            ) : (
              <TareaCard
                key={f.id}
                tarea={f.tarea}
                hilosDisponibles={hilos}
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
          onClose={() => setCreandoTarea(false)}
        />
      )}
      {creandoHilo && (
        <HiloFormPanel
          onClose={() => setCreandoHilo(false)}
        />
      )}
    </div>
  );
}
