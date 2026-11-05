"use client";

import { useState } from "react";
import { Archive } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { Volver } from "@/components/ui/Volver";
import type { Moneda } from "@/lib/monedas";
import { CLASE_NIVEL, textoCambio } from "@/lib/niveles";
import { formatFechaHora } from "@/lib/utils";
import { activarPorcentaje, revertirPorcentaje } from "../actions";
import { PASO, textoBase, textoMinimo, textoPorcentaje } from "../etiquetas";
import type { Categoria, FilaHistoria, Porcentaje } from "../types";
import { PorcentajeFormPanel } from "./PorcentajeFormPanel";

// La ruta de los avisos de un cambio (`/catalogo/porcentajes/<id>`): el gerente llega acá a revertirlo.
// Solo se revierte el último cambio; para uno anterior, se revierten de a uno desde arriba.
export function PorcentajeFicha({
  porcentaje,
  historia,
  categoriasInsumo,
  categoriasServicio,
  puedeEditar,
  monedaPrincipal,
}: {
  porcentaje: Porcentaje;
  historia: FilaHistoria[];
  categoriasInsumo: Categoria[];
  categoriasServicio: Categoria[];
  puedeEditar: boolean;
  monedaPrincipal: Moneda;
}) {
  const [editando, setEditando] = useState(false);
  const [revirtiendo, setRevirtiendo] = useState<FilaHistoria | null>(null);
  const [rojo, setRojo] = useState<FilaHistoria | null>(null);
  const [baja, setBaja] = useState(false);
  const nombreCategoria = new Map([...categoriasInsumo, ...categoriasServicio].map((c) => [c.id, c.nombre]));

  async function revertir(fila: FilaHistoria, confirmarRojo: boolean) {
    const r = await revertirPorcentaje({ valor_id: fila.id, confirmar_rojo: confirmarRojo });
    if ("pideConfirmar" in r) {
      setRojo(fila);
      return;
    }
    if (!r.success) toast.error(r.error);
    else toast.success("Cambio revertido. A quien lo hizo le llega un aviso.");
  }

  async function activar(activo: boolean) {
    const r = await activarPorcentaje({ id: porcentaje.id, activo });
    if (!r.success) toast.error(r.error);
    else toast.success(activo ? `Se reactivó ${porcentaje.nombre}` : `Se dio de baja ${porcentaje.nombre}`);
  }

  return (
    <div className="flex flex-col gap-6">
      <Volver href="/catalogo/porcentajes">Servicios en %</Volver>

      <section className="card flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="t-h2 min-w-0 flex-1">
            {porcentaje.nombre} · {textoPorcentaje(porcentaje.porcentaje)}
          </h2>
          {porcentaje.de_baja && <span className="badge badge-neutral">De baja</span>}
          {puedeEditar &&
            (porcentaje.de_baja ? (
              <button className="btn btn-primary btn-sm" onClick={() => activar(true)}>
                Reactivar
              </button>
            ) : (
              <>
                {/* "Cambiar" a la vista y la baja en el ⋯: pantallas.md → *Baja en el menú*. */}
                <button className="btn btn-secondary btn-sm" onClick={() => setEditando(true)}>
                  Cambiar
                </button>
                <OverflowMenu
                  items={[
                    {
                      label: "Dar de baja",
                      icon: <Archive size={14} />,
                      destructive: true,
                      onClick: () => setBaja(true),
                    },
                  ]}
                />
              </>
            ))}
        </div>
        <p className="t-caption">
          {[
            PASO[porcentaje.paso].titulo,
            textoBase(porcentaje, nombreCategoria),
            textoMinimo(porcentaje),
            porcentaje.opcional && "opcional",
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
      </section>

      <section className="flex flex-col gap-2">
        <h3 className="t-label">Historia</h3>
        <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">
          {historia.map((h, i) => {
            const anterior = historia[i + 1];
            return (
              <li key={h.id} className="row flex flex-col gap-1 border-b border-border last:border-b-0">
                <div className="flex items-baseline justify-between gap-2">
                  <span className="t-body-m font-semibold">
                    {h.de_baja ? "De baja" : `${textoPorcentaje(h.porcentaje)} · ${PASO[h.paso].titulo}`}
                  </span>
                  {anterior && !h.de_baja && anterior.porcentaje !== h.porcentaje && (
                    <span className={h.nivel ? CLASE_NIVEL[h.nivel] : "t-caption"}>
                      {textoCambio(anterior.porcentaje, h.porcentaje)}
                    </span>
                  )}
                </div>
                {!h.de_baja && (
                  <p className="t-caption">
                    {[h.nombre, textoBase(h, nombreCategoria), textoMinimo(h), h.opcional && "opcional"]
                      .filter(Boolean)
                      .join(" · ")}
                  </p>
                )}
                <p className="t-caption">
                  {[
                    !anterior ? "Alta" : h.revierte_id ? "Reversión" : "Cambio",
                    h.cargado_por ?? "—",
                    formatFechaHora(h.created_at),
                  ].join(" · ")}
                </p>
                {puedeEditar && h.ultimo && (
                  <button className="btn btn-ghost btn-sm self-start" onClick={() => setRevirtiendo(h)}>
                    Revertir
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      </section>

      {editando && (
        <PorcentajeFormPanel
          porcentaje={porcentaje}
          categoriasInsumo={categoriasInsumo}
          categoriasServicio={categoriasServicio}
          monedaPrincipal={monedaPrincipal}
          onClose={() => setEditando(false)}
        />
      )}

      {revirtiendo && (
        <ConfirmModal
          title="Revertir el último cambio"
          mensaje={
            historia.length === 1
              ? "Antes del alta no se cobraba: revertirla lo deja de baja. A quien lo cargó le llega un aviso."
              : "Todo vuelve a como estaba antes de este cambio, con un valor nuevo en la historia. A quien lo hizo le llega un aviso."
          }
          confirmLabel="Revertir"
          onClose={() => setRevirtiendo(null)}
          onConfirm={() => revertir(revirtiendo, false)}
        />
      )}

      {rojo && (
        <ConfirmModal
          title="El % cambia 50 % o más"
          mensaje="Al revertir, el % cambia 50 % o más contra el que rige hoy. ¿Está bien?"
          confirmLabel="Sí, revertir"
          onClose={() => setRojo(null)}
          onConfirm={() => revertir(rojo, true)}
        />
      )}

      {baja && (
        <ConfirmModal
          title={`Dar de baja ${porcentaje.nombre}`}
          mensaje="Deja de cobrarse en los precios desde ahora. Queda en la historia y se puede reactivar."
          confirmLabel="Dar de baja"
          onClose={() => setBaja(false)}
          onConfirm={() => activar(false)}
        />
      )}
    </div>
  );
}
