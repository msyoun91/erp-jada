"use client";

import { useState } from "react";
import Link from "next/link";
import { Building2, Calculator, ChevronRight, CircleCheck, FileText, Plus, SearchX, UserRound } from "lucide-react";
import { Paginacion, usePaginado } from "@/components/ui/Paginacion";
import { SearchInput } from "@/components/ui/SearchInput";
import { Vacio } from "@/components/ui/Vacio";
import { ENTES } from "@/lib/entes";
import { formatFecha, hace } from "@/lib/utils";
import type { Pedido, PresupuestoResumen } from "../queries";
import { AltaPresupuestoPanel } from "./AltaPresupuestoPanel";

type Filtro = "todos" | "esperan" | "devueltas";

const FILA = "row flex items-center gap-3 border-b border-border last:border-b-0 hover:bg-bg-subtle";

// En la lista, con la obra debajo; en la ficha de la obra, sin ella.
export function FilaPresupuesto({ p, obra }: { p: Omit<PresupuestoResumen, "obra">; obra?: string }) {
  return (
    <Link href={`/presupuestos/${p.id}`} className={FILA}>
      <div className="min-w-0 flex-1">
        <p className="t-body-m truncate font-medium text-text-primary">
          {p.codigo} · {p.nombre}
        </p>
        {obra && (
          <p className="t-caption flex min-w-0 items-center gap-1">
            <Building2 size={12} className="shrink-0" />
            <span className="truncate">{obra}</span>
          </p>
        )}
      </div>
      <span className={`badge ${ENTES.presupuesto.estados[p.estado].badge}`}>{ENTES.presupuesto.estados[p.estado].label}</span>
      <ChevronRight size={16} className="shrink-0 text-text-tertiary" />
    </Link>
  );
}

function incluye(q: string, ...textos: (string | null)[]) {
  return textos.some((t) => t?.toLowerCase().includes(q));
}

// `esperan` llega solo a quien puede autorizar: sin eso, el filtro no se ofrece.
export function PresupuestosView({
  presupuestos,
  esperan,
  devueltas,
  nombres,
  yo,
  obrasParaAlta,
}: {
  presupuestos: PresupuestoResumen[];
  esperan?: Pedido[];
  devueltas: Pedido[];
  nombres: Record<string, string>;
  yo: string;
  obrasParaAlta?: { id: string; nombre: string }[];
}) {
  const [texto, setTexto] = useState("");
  const [filtro, setFiltro] = useState<Filtro>("todos");
  const [creando, setCreando] = useState(false);

  const q = texto.trim().toLowerCase();
  const quien = (id: string | null) => (id === yo ? "Vos" : ((id && nombres[id]) ?? "—"));
  const pedidos = (filtro === "esperan" ? (esperan ?? []) : devueltas).filter((p) =>
    incluye(q, p.presupuesto.codigo, p.presupuesto.nombre)
  );
  const filtrados = presupuestos.filter((p) => incluye(q, p.codigo, p.nombre, p.obra));
  const paginadoTodos = usePaginado(filtrados);
  const paginadoPedidos = usePaginado(pedidos);

  const filtros: { valor: Filtro; label: string }[] = [
    { valor: "todos", label: "Todos" },
    ...(esperan ? [{ valor: "esperan" as const, label: `Esperan mi autorización (${esperan.length})` }] : []),
    { valor: "devueltas", label: `Devueltas (${devueltas.length})` },
  ];

  return (
    <div>
      {obrasParaAlta && (
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <button className="btn btn-primary" onClick={() => setCreando(true)}>
            <Plus size={16} />
            Nuevo presupuesto
          </button>
          <Link href="/presupuestos/calculadora" className="btn btn-secondary">
            <Calculator size={16} />
            Calculadora
          </Link>
        </div>
      )}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <SearchInput value={texto} onChange={setTexto} placeholder="Buscar por número, nombre u obra…" />
        <div className="segmented" role="group" aria-label="Qué ver">
          {filtros.map((f) => (
            <button
              key={f.valor}
              onClick={() => setFiltro(f.valor)}
              aria-pressed={f.valor === filtro}
              className="segmented-item tap-target"
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {filtro === "todos" ? (
        <>
          <Paginacion {...paginadoTodos} etiqueta="presupuestos" />
          {filtrados.length === 0 ? (
            <Vacio
              icono={presupuestos.length === 0 ? FileText : SearchX}
              titulo={presupuestos.length === 0 ? "Sin presupuestos todavía" : "Sin resultados"}
            >
              {presupuestos.length === 0
                ? "Acá aparecen los presupuestos de las obras que ves."
                : "Probá con otro término."}
            </Vacio>
          ) : (
            <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
              {paginadoTodos.visibles.map((p) => (
                <FilaPresupuesto key={p.id} p={p} obra={p.obra} />
              ))}
            </div>
          )}
        </>
      ) : (
        <>
          <Paginacion {...paginadoPedidos} etiqueta="versiones" />
          {pedidos.length === 0 ? (
            q ? (
              <Vacio icono={SearchX} titulo="Sin resultados">
                Probá con otro término.
              </Vacio>
            ) : (
              <Vacio
                icono={CircleCheck}
                color="text-success"
                titulo={filtro === "esperan" ? "Nada espera tu autorización" : "Sin devoluciones por corregir"}
              />
            )
          ) : (
            <div className="flex flex-col rounded-lg border border-border bg-bg-surface">
              {paginadoPedidos.visibles.map((p) => (
                <Link key={p.id} href={`/presupuestos/${p.presupuesto.id}/${p.version.id}`} className={FILA}>
                  <div className="min-w-0 flex-1">
                    <p className="t-body-m truncate font-medium text-text-primary">
                      {p.presupuesto.codigo} · {p.presupuesto.nombre} · v{p.version.numero}
                    </p>
                    <p className="t-body-m">{filtro === "esperan" ? p.texto : p.motivo}</p>
                    <p className="t-caption flex items-center gap-1">
                      <UserRound size={12} className="shrink-0" />
                      {filtro === "esperan"
                        ? `${quien(p.pedido_por)} · ${hace(p.created_at)}`
                        : `Devolvió ${quien(p.resuelto_por)}${p.resuelto_en ? ` · ${formatFecha(p.resuelto_en)}` : ""}`}
                    </p>
                  </div>
                  <ChevronRight size={16} className="shrink-0 text-text-tertiary" />
                </Link>
              ))}
            </div>
          )}
        </>
      )}
    {creando && obrasParaAlta && <AltaPresupuestoPanel obras={obrasParaAlta} onClose={() => setCreando(false)} />}
    </div>
  );
}
