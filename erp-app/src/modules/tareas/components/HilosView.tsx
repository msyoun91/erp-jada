"use client";

import { useState } from "react";
import Link from "next/link";
import { ChevronRight, Plus, Repeat, UserRound } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { hoyISO } from "@/lib/utils";
import { estaAbierto, estaVencido } from "../derivados";
import { ESTADO_HILO, textoRecurrencia } from "../etiquetas";
import type { HiloResumen } from "../queries";
import { HiloFormPanel } from "./HiloFormPanel";

const ESTADOS = [
  { valor: "abierto", label: "Abiertos" },
  { valor: "cerrado", label: "Cerrados" },
  { valor: "todos", label: "Todos" },
] as const;

type Filtro = (typeof ESTADOS)[number]["valor"];

export function HilosView({
  hilos,
  yo,
  nombres,
  equipo = false,
}: {
  hilos: HiloResumen[];
  yo: string;
  nombres: Record<string, string>;
  // En la bandeja de Equipo: sin crear, que un hilo nuevo es de quien lo crea.
  equipo?: boolean;
}) {
  const [texto, setTexto] = useState("");
  const [estado, setEstado] = useState<Filtro>("abierto");
  const [creando, setCreando] = useState(false);
  const hoy = hoyISO();

  const q = texto.trim().toLowerCase();
  const filtrados = hilos.filter(
    (h) => (estado === "todos" || h.estado === estado) && h.titulo.toLowerCase().includes(q)
  );
  const { visibles, ...paginado } = usePaginado(filtrados);

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar hilo…" />
        <select
          className="input w-auto"
          value={estado}
          onChange={(e) => setEstado(e.target.value as Filtro)}
          aria-label="Filtrar por estado"
        >
          {ESTADOS.map((e) => (
            <option key={e.valor} value={e.valor}>
              {e.label}
            </option>
          ))}
        </select>
        {!equipo && (
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nuevo hilo
          </button>
        )}
      </div>

      <Paginacion {...paginado} etiqueta="hilos" />

      {filtrados.length === 0 ? (
        <div className="empty-state">
          <p className="t-h3">{hilos.length === 0 ? "Sin hilos todavía" : "Sin resultados"}</p>
          <p className="t-body-m mt-1">
            {hilos.length === 0
              ? equipo
                ? "Acá aparecen los hilos donde participa alguien del equipo."
                : 'Acá aparecen los hilos que llevás y los que tienen un paso tuyo. Creá uno con "Nuevo hilo".'
              : "Probá con otro término o cambiá el filtro de estado."}
          </p>
        </div>
      ) : (
        <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {visibles.map((h) => {
            const pasos = h.tareas.filter((t) => t.activo && t.estado !== "cancelada");
            const completados = pasos.filter((t) => t.estado === "completada").length;
            const mios = pasos.filter((t) => t.asignado_id === yo && estaAbierto(t.estado)).length;
            const vencidos = pasos.filter((t) => estaVencido(t, hoy)).length;
            const recurrencia = textoRecurrencia(h.recurrencia_cantidad, h.recurrencia_unidad);
            return (
              <Link
                key={h.id}
                href={`/tareas/${h.id}`}
                className="flex items-center gap-3 border-b border-border row last:border-b-0 hover:bg-bg-subtle"
              >
                <div className="min-w-0 flex-1">
                  <p className="t-body-m truncate font-medium text-text-primary">{h.titulo}</p>
                  <p className="t-caption flex flex-wrap items-center gap-x-3 gap-y-1">
                    <span className="flex items-center gap-1">
                      <UserRound size={12} strokeWidth={1.75} />
                      {h.responsable_id === yo ? "Vos" : (nombres[h.responsable_id] ?? "—")}
                    </span>
                    <span>
                      {completados}/{pasos.length} completados
                    </span>
                    {mios > 0 && (
                      <span className="text-text-brand">
                        {mios} {mios === 1 ? "paso tuyo" : "pasos tuyos"}
                      </span>
                    )}
                    {vencidos > 0 && (
                      <span className="text-error-text">
                        {vencidos} {vencidos === 1 ? "vencido" : "vencidos"}
                      </span>
                    )}
                    {recurrencia && (
                      <span className="flex items-center gap-1">
                        <Repeat size={12} strokeWidth={1.75} />
                        {recurrencia}
                      </span>
                    )}
                  </p>
                </div>
                <span className={`badge ${ESTADO_HILO[h.estado].badge}`}>{ESTADO_HILO[h.estado].label}</span>
                <ChevronRight size={16} strokeWidth={1.75} className="shrink-0 text-text-tertiary" />
              </Link>
            );
          })}
        </div>
      )}

      {creando && <HiloFormPanel onClose={() => setCreando(false)} />}
    </div>
  );
}
