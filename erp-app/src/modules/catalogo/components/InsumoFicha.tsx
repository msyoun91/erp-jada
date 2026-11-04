"use client";

import { useState } from "react";
import { Archive } from "lucide-react";
import { toast } from "sonner";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { RightPanel } from "@/components/ui/RightPanel";
import { activarInsumo, avisoBaja, quitarColor, sumarColor } from "../actions";
import { POR_UNIDAD, UNIDAD, hace, textoCosto, textoNumero } from "../etiquetas";
import type { AvisoBaja, Categoria, Color, Insumo, TipoInsumo, Variante } from "../types";
import { BajaModal } from "./BajaModal";

type Baja = { variante: Variante | null; aviso: AvisoBaja };

export function InsumoFicha({
  tipo,
  insumo,
  categorias,
  colores,
  puedeEditar,
  puedeCostos,
  onEditar,
  onCostos,
  onClose,
}: {
  tipo: TipoInsumo;
  insumo: Insumo;
  categorias: Categoria[];
  colores: Color[];
  puedeEditar: boolean;
  puedeCostos: boolean;
  onEditar: () => void;
  onCostos: () => void;
  onClose: () => void;
}) {
  const [baja, setBaja] = useState<Baja | null>(null);
  const [colorNuevo, setColorNuevo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const nombreColor = new Map(colores.map((c) => [c.id, c.nombre]));
  const categoria = categorias.find((c) => c.id === insumo.categoria_id);
  const activas = insumo.variantes.filter((v) => v.activo);
  const sumables = colores.filter((c) => c.activo && !activas.some((v) => v.color_id === c.id));

  async function pedirBaja(variante: Variante | null) {
    setEnviando(true);
    const r = await avisoBaja({ insumo_id: insumo.id, variante_id: variante?.id ?? null });
    setEnviando(false);
    if (!r.success) toast.error(r.error);
    else setBaja({ variante, aviso: r.aviso });
  }

  async function confirmarBaja(b: Baja) {
    const r = b.variante ? await quitarColor(b.variante.id) : await activarInsumo({ id: insumo.id, activo: false });
    if (!r.success) toast.error(r.error);
    else
      toast.success(
        b.variante ? `Se quitó ${nombreColor.get(b.variante.color_id ?? "")}` : `Se dio de baja ${insumo.nombre}`,
      );
  }

  async function reactivar() {
    setEnviando(true);
    const r = await activarInsumo({ id: insumo.id, activo: true });
    setEnviando(false);
    if (!r.success) toast.error(r.error);
    else toast.success(`Se reactivó ${insumo.nombre}. Los paquetes que bajó no vuelven solos.`);
  }

  async function sumar() {
    setEnviando(true);
    const r = await sumarColor({ insumo_id: insumo.id, color_id: colorNuevo });
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success(
      `Se sumó ${nombreColor.get(colorNuevo)}${puedeCostos ? "" : ". A quienes cargan costos les llega un aviso."}`,
    );
    setColorNuevo("");
  }

  const datos = [
    categoria?.nombre,
    UNIDAD[insumo.unidad],
    tipo === "insumo" &&
      (insumo.peso === null ? "sin peso" : `${textoNumero(insumo.peso)} kg/${POR_UNIDAD[insumo.unidad]}`),
    tipo === "insumo" && (insumo.espesor === null ? "sin espesor" : `${textoNumero(insumo.espesor)} mm de espesor`),
  ].filter(Boolean);

  return (
    <>
      <RightPanel
        title={insumo.nombre}
        subtitle={datos.join(" · ")}
        onClose={onClose}
        footer={
          <div className="flex flex-wrap items-center gap-2">
            {puedeEditar && insumo.activo && (
              <button className="btn btn-secondary" onClick={onEditar}>
                Editar
              </button>
            )}
            {puedeCostos && insumo.activo && activas.length > 0 && (
              <button className="btn btn-secondary" onClick={onCostos}>
                Cargar costo
              </button>
            )}
            {puedeEditar &&
              (insumo.activo ? (
                <OverflowMenu
                  items={[
                    {
                      label: "Dar de baja",
                      icon: <Archive size={14} strokeWidth={1.75} />,
                      destructive: true,
                      onClick: () => pedirBaja(null),
                    },
                  ]}
                />
              ) : (
                <button className="btn btn-primary" onClick={reactivar} disabled={enviando}>
                  Reactivar
                </button>
              ))}
          </div>
        }
      >
        <div className="flex flex-col gap-4 overflow-y-auto p-5">
          {!insumo.activo && <p className="badge badge-neutral self-start">De baja</p>}

          {(tipo === "insumo" || puedeCostos) && (
            <section className="flex flex-col gap-2">
              <h3 className="t-label">
                {tipo === "servicio" ? "Costo" : insumo.con_color ? "Colores" : "Color indistinto"}
              </h3>
              {insumo.con_color && activas.length === 0 && (
                <p className="t-body-m text-warning-text">Sin colores: sumá al menos uno para poder usarlo.</p>
              )}
              <ul className="flex flex-col">
                {activas.map((v) => (
                  <li
                    key={v.id}
                    className="flex items-center justify-between gap-2 border-b border-border py-2 last:border-b-0"
                  >
                    <div className="min-w-0">
                      {v.color_id && <p className="t-body-m font-medium">{nombreColor.get(v.color_id)}</p>}
                      {puedeCostos && (
                        <p className={v.costo ? "t-body-m" : "t-body-m text-warning-text"}>
                          {v.costo ? `${textoCosto(v.costo, insumo.unidad)} · ${hace(v.costo.desde)}` : "Sin costo"}
                        </p>
                      )}
                    </div>
                    {puedeEditar && insumo.activo && v.color_id && (
                      <button className="btn btn-ghost btn-sm" onClick={() => pedirBaja(v)} disabled={enviando}>
                        Quitar
                      </button>
                    )}
                  </li>
                ))}
              </ul>
              {puedeEditar && insumo.activo && insumo.con_color && sumables.length > 0 && (
                <div className="flex gap-2">
                  <select
                    aria-label="Color para sumar"
                    className="input"
                    value={colorNuevo}
                    onChange={(e) => setColorNuevo(e.target.value)}
                  >
                    <option value="">Sumar un color…</option>
                    {sumables.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.nombre}
                      </option>
                    ))}
                  </select>
                  <button className="btn btn-secondary shrink-0" onClick={sumar} disabled={!colorNuevo || enviando}>
                    Sumar
                  </button>
                </div>
              )}
              {insumo.con_color && (
                <p className="t-caption">
                  Un color nuevo no se vende hasta que una versión del paquete lo ofrezca. Volver a sumar uno que se
                  quitó lo trae con sus costos.
                </p>
              )}
            </section>
          )}
        </div>
      </RightPanel>

      {baja && (
        <BajaModal
          titulo={
            baja.variante
              ? `Quitar ${nombreColor.get(baja.variante.color_id ?? "")} de ${insumo.nombre}`
              : `Dar de baja ${insumo.nombre}`
          }
          aviso={baja.aviso}
          onConfirm={() => confirmarBaja(baja)}
          onClose={() => setBaja(null)}
        />
      )}
    </>
  );
}
