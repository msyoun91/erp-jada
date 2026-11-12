"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { History, Layers, ListChecks, Pencil, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA } from "@/lib/monedas";
import { cambiarTodasLasSecciones, guardarDatosVersion, mantenerRenglones } from "../actions";
import type { OpcionalVersion, VersionEditor } from "../queries";
import {
  ALICUOTAS,
  datosVersionSchema,
  formatAlicuota,
  todasSeccionesSchema,
  type DatosVersionForm,
  type TodasSeccionesForm,
} from "../types";
import { OpcionalesPanel } from "./Opcionales";

type Version = VersionEditor["version"];

export function AccionesVersion({
  version,
  tope,
  secciones,
  opcionales,
  renglones,
}: {
  version: Version;
  tope: number | null;
  secciones: VersionEditor["secciones"];
  opcionales: OpcionalVersion[];
  renglones: VersionEditor["renglones"];
}) {
  const [abierto, setAbierto] = useState<"datos" | "secciones" | "opcionales" | "a_hoy" | "mantener" | null>(null);
  const cerrar = () => setAbierto(null);
  // A hoy van las ventanas y los mínimos: también actualiza lo que ya estaba a hoy y cambió de precio.
  const deCatalogo = renglones.filter((r) => r.tipo !== "mano");
  const mantenidos = deCatalogo.filter((r) => r.mantener).length;
  const mantenibles = deCatalogo.filter((r) => r.mantener_en && !r.mantener);
  const items = [
    ...(secciones.length > 1
      ? [{ label: "Todas las secciones…", icon: <Layers size={14} />, onClick: () => setAbierto("secciones") }]
      : []),
    ...(opcionales.length > 0
      ? [{ label: "Cómo se ven los opcionales…", icon: <ListChecks size={14} />, onClick: () => setAbierto("opcionales") }]
      : []),
    ...(mantenibles.length > 0
      ? [{ label: "Mantener todas…", icon: <History size={14} />, onClick: () => setAbierto("mantener") }]
      : []),
    ...(deCatalogo.length > 0
      ? [{ label: "Todas a hoy…", icon: <RefreshCw size={14} />, onClick: () => setAbierto("a_hoy") }]
      : []),
  ];

  async function mantener(ids: string[], si: boolean) {
    const result = await mantenerRenglones(version.id, ids, si);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    const sin = result.renglones.filter((r) => r.precio === null).length;
    if (sin > 0) toast.warning(sin === 1 ? "1 ventana quedó sin precio" : `${sin} ventanas quedaron sin precio`);
    else toast.success(si ? (ids.length === 1 ? "1 renglón mantenido" : `${ids.length} renglones mantenidos`) : "Todo a hoy");
  }
  return (
    <>
      <button type="button" className="btn btn-secondary btn-sm" onClick={() => setAbierto("datos")}>
        <Pencil size={14} />
        Editar
      </button>
      {items.length > 0 && <OverflowMenu items={items} />}
      {abierto === "datos" && <DatosVersionPanel version={version} tope={tope} onClose={cerrar} />}
      {abierto === "secciones" && <TodasSeccionesPanel versionId={version.id} onClose={cerrar} />}
      {abierto === "opcionales" && (
        <OpcionalesPanel versionId={version.id} opcionales={opcionales} secciones={secciones} onClose={cerrar} />
      )}
      {abierto === "mantener" && (
        <ConfirmModal
          title="Mantener todas"
          mensaje={`${
            mantenibles.length === 1 ? "El renglón copiado vuelve" : `Los ${mantenibles.length} renglones copiados vuelven`
          } a los precios de la versión de la que salió esta. Mantener pide autorización del jefe comercial, aunque el precio no cambie.`}
          confirmLabel="Mantener"
          onConfirm={() => mantener(mantenibles.map((r) => r.id), true)}
          onClose={cerrar}
        />
      )}
      {abierto === "a_hoy" && (
        <ConfirmModal
          title="Todas a hoy"
          mensaje={`Las ventanas y los mínimos se recalculan con los precios de hoy.${
            mantenidos === 0
              ? ""
              : mantenidos === 1
                ? " El mantenido deja de estarlo."
                : ` Los ${mantenidos} mantenidos dejan de estarlo.`
          }`}
          confirmLabel="Pasar a hoy"
          onConfirm={() => mantener(deCatalogo.map((r) => r.id), false)}
          onClose={cerrar}
        />
      )}
    </>
  );
}

const DATOS_FORM = "presupuesto-version-datos";

function DatosVersionPanel({ version: v, tope, onClose }: { version: Version; tope: number | null; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<DatosVersionForm>({
    resolver: zodResolver(datosVersionSchema),
    defaultValues: {
      id: v.id,
      variante_nombre: v.variante_nombre ?? "",
      iva_discriminado: v.iva_discriminado,
      descuento: v.descuento,
      condiciones: v.condiciones ?? "",
    },
  });
  const { errors } = formState;

  async function onSubmit(data: DatosVersionForm) {
    setEnviando(true);
    const result = await guardarDatosVersion(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Versión guardada");
    onClose();
  }

  return (
    <RightPanel
      title={`Versión ${v.numero}`}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<PiePanel confirmar="Guardar" enviando={enviando} onCancelar={onClose} form={DATOS_FORM} />}
    >
      <form id={DATOS_FORM} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="ver-variante" label="Nombre de la variante" error={errors.variante_nombre}>
          <input id="ver-variante" placeholder="Ej: Aluminio" className={claseInput(errors.variante_nombre)} {...register("variante_nombre")} />
          <p className="t-caption mt-1">Lo ve el cliente. Hace falta si el presupuesto tiene otra variante publicada.</p>
        </Campo>
        <Campo id="ver-iva" label="IVA" requerido error={errors.iva_discriminado}>
          <select
            id="ver-iva"
            aria-required
            className={claseInput(errors.iva_discriminado)}
            {...register("iva_discriminado", { setValueAs: (x: unknown) => x === true || x === "true" })}
          >
            <option value="true">Discriminado</option>
            <option value="false">Incluido en cada precio</option>
          </select>
        </Campo>
        <Campo id="ver-descuento" label="Descuento (%)" error={errors.descuento}>
          <input
            id="ver-descuento"
            type="number"
            step="any"
            min="0"
            max="100"
            inputMode="decimal"
            className={claseInput(errors.descuento)}
            {...register("descuento")}
          />
          <p className="t-caption mt-1">
            {tope === null
              ? "Gerencia todavía no configuró el tope: cualquier descuento pide autorización."
              : `Hasta ${formatAlicuota(tope)} no pide autorización.`}
          </p>
        </Campo>
        <Campo id="ver-condiciones" label="Condiciones particulares" error={errors.condiciones}>
          <textarea
            id="ver-condiciones"
            rows={5}
            placeholder="Ej: Entrega en 60 días desde la seña."
            className={claseInput(errors.condiciones)}
            {...register("condiciones")}
          />
          <p className="t-caption mt-1">
            Las de esta obra. Van al cliente junto con los términos generales de Configuración, que se toman al publicar.
          </p>
        </Campo>
      </form>
    </RightPanel>
  );
}

const SECCIONES_FORM = "presupuesto-todas-secciones";

function TodasSeccionesPanel({ versionId, onClose }: { versionId: string; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<TodasSeccionesForm>({
    resolver: zodResolver(todasSeccionesSchema),
    defaultValues: { version_id: versionId, moneda: "", alicuota: "" },
  });
  const { errors } = formState;

  async function onSubmit(data: TodasSeccionesForm) {
    setEnviando(true);
    const result = await cambiarTodasLasSecciones(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Secciones cambiadas");
    onClose();
  }

  return (
    <RightPanel
      title="Todas las secciones"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <PiePanel
          confirmar="Cambiar todas"
          enviando={enviando}
          onCancelar={onClose}
          form={SECCIONES_FORM}
          nota="Con otra moneda, las ventanas se recalculan."
        />
      }
    >
      <form id={SECCIONES_FORM} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="todas-moneda" label="Moneda" error={errors.moneda}>
          <select id="todas-moneda" className={claseInput(errors.moneda)} {...register("moneda")}>
            <option value="">Como está cada una</option>
            {MONEDAS_LISTA.map((m) => (
              <option key={m} value={m}>
                {MONEDAS[m]}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="todas-alicuota" label="IVA" error={errors.alicuota}>
          <select id="todas-alicuota" className={claseInput(errors.alicuota)} {...register("alicuota")}>
            <option value="">Como está cada una</option>
            {ALICUOTAS.map((a) => (
              <option key={a} value={a}>
                {formatAlicuota(a)}
              </option>
            ))}
          </select>
        </Campo>
      </form>
    </RightPanel>
  );
}
