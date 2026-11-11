"use client";

import { useState } from "react";
import { ArrowRightLeft, Copy, History, Package, Pencil, Plus, RefreshCw, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { formatFecha } from "@/lib/utils";
import { mantenerRenglones, moverRenglon, sacarRenglon } from "../actions";
import type { VersionEditor } from "../queries";
import type { FormularioVenta } from "../types";
import { opcionSeccion, RenglonCatalogoPanel, RenglonManoPanel, type Contexto } from "./RenglonPanel";

type Renglon = VersionEditor["renglones"][number];

// Al pie de cada sección, los dos que carga quien arma. Los mínimos los pone la base.
export function AgregarRenglon({ seccionId, ...ctx }: Contexto & { seccionId: string }) {
  const [abierto, setAbierto] = useState<"catalogo" | "mano" | null>(null);
  const cerrar = () => setAbierto(null);
  return (
    <div className="mt-3 flex flex-wrap gap-2">
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto("catalogo")}>
        <Package size={14} />
        De Catálogo
      </button>
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto("mano")}>
        <Plus size={14} />A mano
      </button>
      {abierto === "catalogo" && <RenglonCatalogoPanel {...ctx} seccionId={seccionId} onClose={cerrar} />}
      {abierto === "mano" && <RenglonManoPanel {...ctx} seccionId={seccionId} onClose={cerrar} />}
    </div>
  );
}

type Abierto =
  | { modo: "editar" | "duplicar"; formulario: FormularioVenta | null }
  | { modo: "sacar" | "mover" }
  | null;

// `nombre`: el que ve el cliente (el paquete o la descripción), para el que no tiene designación. `children`: el
// encabezado de la fila.
export function AccionesRenglon({
  renglon: r,
  nombre,
  children,
  ...ctx
}: Contexto & { renglon: Renglon; nombre: string; children: React.ReactNode }) {
  const [abierto, setAbierto] = useState<Abierto>(null);
  const cerrar = () => setAbierto(null);
  const etiqueta = [r.designacion ?? nombre, r.ubicacion].filter(Boolean).join(" · ");

  // El panel de una ventana arranca con lo cargado, con el formulario de su paquete que ya trajo la versión.
  function abrir(modo: "editar" | "duplicar") {
    setAbierto({ modo, formulario: r.paquete_id ? (ctx.formularios[r.paquete_id] ?? null) : null });
  }

  async function sacar() {
    const result = await sacarRenglon(r.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Renglón sacado");
  }

  // Cada clic guarda, como los opcionales: se deshace con el otro.
  async function mantener(si: boolean) {
    const result = await mantenerRenglones(ctx.versionId, [r.id], si);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    const [q] = result.renglones;
    if (q.precio === null) toast.warning(`${etiqueta} quedó sin precio: ${q.mensaje ?? "revisá lo cargado"}`);
    else toast.success(si && r.mantener_en ? `${etiqueta}, con los precios del ${formatFecha(r.mantener_en)}` : `${etiqueta}, a hoy`);
  }

  // A hoy también actualiza lo que ya estaba a hoy y cambió de precio: "actualizala o mantenela" (*Antes de publicar*).
  const precios =
    r.tipo === "mano"
      ? []
      : r.mantener
        ? [{ label: "Pasar a hoy", icon: <RefreshCw size={14} />, onClick: () => mantener(false) }]
        : [
            { label: "Actualizar a hoy", icon: <RefreshCw size={14} />, onClick: () => mantener(false) },
            ...(r.mantener_en
              ? [{ label: `Mantener precios del ${formatFecha(r.mantener_en)}`, icon: <History size={14} />, onClick: () => mantener(true) }]
              : []),
          ];
  // Del mínimo, quien arma solo elige la sección (PR012) y si se mantiene.
  const items =
    r.tipo === "minimo"
      ? [
          ...precios,
          ...(ctx.secciones.length > 1
            ? [{ label: "Mover de sección", icon: <ArrowRightLeft size={14} />, onClick: () => setAbierto({ modo: "mover" as const }) }]
            : []),
        ]
      : [
          { label: "Editar", icon: <Pencil size={14} />, onClick: () => abrir("editar") },
          { label: "Duplicar", icon: <Copy size={14} />, onClick: () => abrir("duplicar") },
          ...precios,
          { label: "Sacar", icon: <Trash2 size={14} />, onClick: () => setAbierto({ modo: "sacar" }), destructive: true },
        ];
  if (items.length === 0) return children;

  return (
    <>
      {r.tipo === "minimo" ? (
        children
      ) : (
        // Atajo de `⋯` → Editar para el dedo y el mouse; con teclado se entra por el menú. Seleccionar texto no edita.
        <div
          className="flex min-w-0 flex-1 cursor-pointer items-start gap-3"
          onClick={() => {
            if (!window.getSelection()?.toString()) abrir("editar");
          }}
        >
          {children}
        </div>
      )}
      <OverflowMenu items={items} />
      {(abierto?.modo === "editar" || abierto?.modo === "duplicar") &&
        (r.tipo === "catalogo" ? (
          <RenglonCatalogoPanel
            {...ctx}
            seccionId={r.seccion_id}
            renglon={r}
            nombre={nombre}
            duplicar={abierto.modo === "duplicar"}
            formulario={abierto.formulario}
            onClose={cerrar}
          />
        ) : (
          <RenglonManoPanel
            {...ctx}
            seccionId={r.seccion_id}
            renglon={r}
            duplicar={abierto.modo === "duplicar"}
            onClose={cerrar}
          />
        ))}
      {abierto?.modo === "mover" && <MoverPanel renglon={r} nombre={nombre} secciones={ctx.secciones} onClose={cerrar} />}
      {abierto?.modo === "sacar" && (
        <ConfirmModal
          title="Sacar el renglón"
          mensaje={`"${etiqueta}" deja de estar en esta versión.`}
          confirmLabel="Sacar"
          onConfirm={sacar}
          onClose={cerrar}
        />
      )}
    </>
  );
}

function MoverPanel({
  renglon,
  nombre,
  secciones,
  onClose,
}: {
  renglon: Renglon;
  nombre: string;
  secciones: Contexto["secciones"];
  onClose: () => void;
}) {
  const [seccion, setSeccion] = useState(renglon.seccion_id);
  const [enviando, setEnviando] = useState(false);

  async function mover() {
    setEnviando(true);
    const result = await moverRenglon(renglon.id, seccion);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Renglón movido");
    onClose();
  }

  return (
    <RightPanel
      title="Mover de sección"
      subtitle={nombre}
      onClose={onClose}
      hayCambios={seccion !== renglon.seccion_id}
      footer={
        <PiePanel
          confirmar="Mover"
          enviando={enviando}
          onCancelar={onClose}
          onConfirmar={mover}
          deshabilitado={seccion === renglon.seccion_id}
          nota="El mínimo lo pone y lo saca la base; en otra moneda, se recalcula en esa."
        />
      }
    >
      <div className="flex flex-col gap-4 px-5 py-4">
        <label className="flex flex-col gap-1">
          <span className="t-label">Sección</span>
          <select className="input" value={seccion} onChange={(e) => setSeccion(e.target.value)}>
            {secciones.map((s) => (
              <option key={s.id} value={s.id}>
                {opcionSeccion(s)}
              </option>
            ))}
          </select>
        </label>
      </div>
    </RightPanel>
  );
}
