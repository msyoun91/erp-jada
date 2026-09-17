"use client";

import { useEffect, useState, useTransition } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { toast } from "sonner";
import { Archive, Pencil, Plus } from "lucide-react";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { ENTES, LABEL_ROL } from "@/lib/entes";
import { activarPlantilla, desactivarPlantilla } from "../actions";
import type { Ente, PlantillaCompleta, TipoEvento, TipoPlantilla } from "../types";
import { PlantillaFormPanel } from "./PlantillaFormPanel";
import { UsarPlantillaPanel } from "./UsarPlantillaPanel";
import { useTareasContexto } from "./tareasContexto";

const TIPO_LABEL: Record<TipoPlantilla, string> = { tarea: "Tarea", hilo: "Hilo", proyecto: "Proyecto" };

// Corre para quien hace el cambio (sql/055), así que la frase le habla a
// quien la lee.
function cuandoCorre(p: PlantillaCompleta) {
  const ente = p.disparo_ente ? ENTES[p.disparo_ente] : undefined;
  const un = ente?.un ?? "un registro";
  const estado = p.disparo_estado ? (ente?.estados?.[p.disparo_estado] ?? p.disparo_estado) : "";
  const [enteRol = "", rol = ""] = (p.disparo_rol ?? "").split(":");
  const nombreRol = LABEL_ROL[enteRol]?.[rol] ?? rol;
  const cuando: Record<TipoEvento, string> = {
    alta: `creás ${un}`,
    estado: `pasás ${un} a «${estado}»`,
    relacion_alta: `a ${un} le sumás el rol «${nombreRol}»`,
    relacion_baja: `a ${un} le sacás el rol «${nombreRol}»`,
    baja: `das de baja ${un}`,
    reactivacion: `reactivás ${un}`,
  };
  return `Corre sola cuando ${cuando[p.disparo_evento ?? "estado"]}, si la tenés activada.`;
}

export function PlantillasView({
  plantillas,
  entes,
  puedeSistema,
  puedeCrearProyecto,
}: {
  plantillas: PlantillaCompleta[];
  entes: Ente[];
  puedeSistema: boolean;
  puedeCrearProyecto: boolean;
}) {
  const { usuarioActualId } = useTareasContexto();
  const router = useRouter();
  const pathname = usePathname();
  const sp = useSearchParams();
  // Deep link desde la campanita (`?plantilla=`), leído una sola vez: arranca
  // filtrando por esa plantilla y el efecto de abajo lo saca de la URL.
  const plantillaParam = sp.get("plantilla");
  const [texto, setTexto] = useState(() => plantillas.find((p) => p.id === plantillaParam)?.nombre ?? "");
  const [creando, setCreando] = useState(false);
  const [editando, setEditando] = useState<PlantillaCompleta | null>(null);
  const [usando, setUsando] = useState<PlantillaCompleta | null>(null);
  const [desactivando, setDesactivando] = useState<PlantillaCompleta | null>(null);
  const [activando, startActivar] = useTransition();

  useEffect(() => {
    if (!plantillaParam) return;
    const p = new URLSearchParams(sp);
    p.delete("plantilla");
    const qs = p.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname, { scroll: false });
    // Se lee una sola vez, al montar con el parámetro puesto.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Espejo de `puede_gestionar_plantilla` (sql/053): ofrecer lo que la RLS
  // después rechaza sería mentir. La barrera sigue siendo la base.
  const puedeGestionar = (p: PlantillaCompleta) =>
    p.alcance === "sistema" ? puedeSistema : p.creado_por === usuarioActualId;

  async function onDesactivar(plantilla: PlantillaCompleta) {
    const result = await desactivarPlantilla(plantilla.id);
    if (!result.success) toast.error(result.error);
    else toast.success("Plantilla desactivada");
  }

  function onActivar(plantilla: PlantillaCompleta, activa: boolean) {
    startActivar(async () => {
      const result = await activarPlantilla({ plantilla_id: plantilla.id, activa });
      if (!result.success) toast.error(result.error);
      else toast.success(activa ? "Activada para vos" : "Apagada para vos");
    });
  }

  const q = texto.trim().toLowerCase();
  const filtradas = plantillas.filter(
    (p) => p.nombre.toLowerCase().includes(q) || (p.descripcion ?? "").toLowerCase().includes(q),
  );
  const { visibles, ...paginado } = usePaginado(filtradas);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar plantilla…" />
        <button data-tour="tareas_plantillas_crear" className="btn btn-primary" onClick={() => setCreando(true)}>
          <Plus size={16} />
          Nueva plantilla
        </button>
      </div>

      <Paginacion {...paginado} etiqueta="plantillas" />

      {filtradas.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{texto ? "Sin resultados" : "Sin plantillas todavía"}</p>
          <p className="t-body-m mt-1">
            {texto ? "Probá con otro término de búsqueda." : "Creá la primera con «Nueva plantilla»."}
          </p>
        </div>
      ) : (
        <div data-tour="tareas_plantillas_lista" className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((p) => {
            const proyectoSinPermiso = p.tipo === "proyecto" && !puedeCrearProyecto;
            return (
              <div key={p.id} className="border-b border-border row last:border-b-0">
                <div className="flex items-center gap-2">
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <p className="t-body-m truncate font-medium text-text-primary">{p.nombre}</p>
                      <span className={`badge shrink-0 ${p.alcance === "sistema" ? "badge-info" : "badge-neutral"}`}>
                        {p.alcance === "sistema" ? "De sistema" : "Privada"}
                      </span>
                      <span className="t-caption shrink-0">{TIPO_LABEL[p.tipo]}</span>
                    </div>
                    {p.descripcion && <p className="t-caption truncate">{p.descripcion}</p>}
                  </div>
                  {/* Con disparador no se usa a mano (TA013): sus textos citan
                      datos del registro que la dispara. */}
                  {p.disparo_ente ? (
                    // Una privada ajena (la ve quien administra) no se activa:
                    // correría con sus cambios (sql/079).
                    (p.alcance === "sistema" || p.creado_por === usuarioActualId) && (
                      <label className="tap-target flex shrink-0 items-center gap-2">
                        <input
                          type="checkbox"
                          checked={p.activada}
                          disabled={activando}
                          onChange={(e) => onActivar(p, e.target.checked)}
                        />
                        <span className="t-body-m">Activada</span>
                      </label>
                    )
                  ) : (
                    <button
                      className="btn btn-secondary btn-sm shrink-0"
                      onClick={() => setUsando(p)}
                      disabled={proyectoSinPermiso}
                    >
                      Usar
                    </button>
                  )}
                  {puedeGestionar(p) && (
                    <OverflowMenu
                      items={[
                        {
                          label: "Modificar",
                          icon: <Pencil size={14} strokeWidth={1.75} />,
                          onClick: () => setEditando(p),
                        },
                        {
                          label: "Desactivar",
                          icon: <Archive size={14} strokeWidth={1.75} />,
                          onClick: () => setDesactivando(p),
                          destructive: true,
                        },
                      ]}
                    />
                  )}
                </div>
                <Contenido plantilla={p} />
                {p.disparo_ente && <p className="t-caption mt-1">{cuandoCorre(p)}</p>}
                {proyectoSinPermiso && (
                  <p className="t-caption mt-1">
                    {p.disparo_ente
                      ? "Crea un proyecto: sin el permiso «Crear proyectos» no va a poder correr para vos."
                      : "Usarla crea un proyecto: necesitás el permiso «Crear proyectos»."}
                  </p>
                )}
              </div>
            );
          })}
        </div>
      )}

      {desactivando && (
        <ConfirmModal
          title="Desactivar plantilla"
          mensaje={`¿Desactivar la plantilla "${desactivando.nombre}"? Lo que ya se creó con ella no se toca.${
            desactivando.disparo_ente ? " Deja de correr para todos los que la activaron." : ""
          }`}
          onConfirm={() => onDesactivar(desactivando)}
          onClose={() => setDesactivando(null)}
        />
      )}

      {creando && <PlantillaFormPanel entes={entes} puedeSistema={puedeSistema} onClose={() => setCreando(false)} />}
      {editando && (
        <PlantillaFormPanel
          plantilla={editando}
          entes={entes}
          puedeSistema={puedeSistema}
          onClose={() => setEditando(null)}
        />
      )}
      {usando && (
        <UsarPlantillaPanel
          plantillas={plantillas.filter((p) => !p.disparo_ente && (p.tipo !== "proyecto" || puedeCrearProyecto))}
          plantillaId={usando.id}
          onClose={() => setUsando(null)}
        />
      )}
    </div>
  );
}

// Qué tiene adentro, en una línea por hilo: la plantilla se elige por su
// contenido, no por el nombre.
function Contenido({ plantilla }: { plantilla: PlantillaCompleta }) {
  const sueltas = plantilla.items.filter((i) => !i.hilo_id);

  if (plantilla.tipo === "proyecto") {
    return (
      <ul className="t-caption mt-2 flex list-disc flex-col gap-1 pl-4">
        {plantilla.hilos.map((h) => (
          <li key={h.id}>
            Hilo «{h.titulo}»: {plantilla.items.filter((i) => i.hilo_id === h.id).map((i) => i.titulo).join(h.encadenada ? " → " : ", ")}
          </li>
        ))}
        {sueltas.length > 0 && <li>Sueltas: {sueltas.map((i) => i.titulo).join(", ")}</li>}
      </ul>
    );
  }

  return (
    <p className="t-caption mt-2">
      {plantilla.tipo === "hilo"
        ? sueltas.map((i) => i.titulo).join(plantilla.encadenada ? " → " : ", ")
        : sueltas[0]?.titulo}
    </p>
  );
}
