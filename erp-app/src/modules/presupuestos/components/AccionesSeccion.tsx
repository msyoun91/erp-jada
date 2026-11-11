"use client";

import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { ArrowDown, ArrowUp, Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { MONEDAS, MONEDAS_LISTA } from "@/lib/monedas";
import { guardarSeccion, ordenarSecciones, sacarSeccion } from "../actions";
import type { VersionEditor } from "../queries";
import { ALICUOTAS, formatAlicuota, seccionSchema, type SeccionForm } from "../types";

type Seccion = VersionEditor["secciones"][number];

// `ids`: todas las secciones de la versión, en el orden en que se ven. Con renglones (o el renglón aparte de un
// opcional) no se ofrece sacar; la única tampoco, para que la versión no quede sin dónde cargar.
export function AccionesSeccion({
  seccion,
  versionId,
  ids,
  conRenglones,
}: {
  seccion: Seccion;
  versionId: string;
  ids: string[];
  conRenglones: boolean;
}) {
  const [abierto, setAbierto] = useState<"editar" | "sacar" | null>(null);
  const i = ids.indexOf(seccion.id);

  async function mover(a: number) {
    const nuevo = [...ids];
    [nuevo[i], nuevo[a]] = [nuevo[a], nuevo[i]];
    const result = await ordenarSecciones(versionId, nuevo);
    if (!result.success) toast.error(result.error);
  }

  async function sacar() {
    const result = await sacarSeccion(seccion.id);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Sección sacada");
  }

  const items = [
    { label: "Editar", icon: <Pencil size={14} />, onClick: () => setAbierto("editar") },
    ...(i > 0 ? [{ label: "Subir", icon: <ArrowUp size={14} />, onClick: () => mover(i - 1) }] : []),
    ...(i < ids.length - 1 ? [{ label: "Bajar", icon: <ArrowDown size={14} />, onClick: () => mover(i + 1) }] : []),
    ...(!conRenglones && ids.length > 1
      ? [{ label: "Sacar", icon: <Trash2 size={14} />, onClick: () => setAbierto("sacar"), destructive: true }]
      : []),
  ];

  return (
    <>
      <OverflowMenu items={items} />
      {abierto === "editar" && <SeccionPanel versionId={versionId} seccion={seccion} orden={seccion.orden} onClose={() => setAbierto(null)} />}
      {abierto === "sacar" && (
        <ConfirmModal
          title="Sacar la sección"
          mensaje={`"${seccion.nombre}" deja de estar en esta versión.`}
          confirmLabel="Sacar"
          onConfirm={sacar}
          onClose={() => setAbierto(null)}
        />
      )}
    </>
  );
}

// Arranca con la moneda y el IVA de la primera sección, y va al final.
export function NuevaSeccion({ versionId, secciones }: { versionId: string; secciones: Seccion[] }) {
  const [abierto, setAbierto] = useState(false);
  const orden = Math.max(-1, ...secciones.map((s) => s.orden)) + 1;
  return (
    <>
      <button type="button" className="btn btn-secondary self-start" onClick={() => setAbierto(true)}>
        <Plus size={14} />
        Nueva sección
      </button>
      {abierto && (
        <SeccionPanel
          versionId={versionId}
          base={secciones[0]}
          orden={orden}
          onClose={() => setAbierto(false)}
        />
      )}
    </>
  );
}

const FORM_ID = "presupuesto-seccion-form";

function SeccionPanel({
  versionId,
  seccion,
  base,
  orden,
  onClose,
}: {
  versionId: string;
  seccion?: Seccion;
  base?: Seccion;
  orden: number;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const desde = seccion ?? base;
  const { register, handleSubmit, formState } = useForm<SeccionForm>({
    resolver: zodResolver(seccionSchema),
    defaultValues: {
      id: seccion?.id,
      version_id: versionId,
      nombre: seccion?.nombre ?? "",
      moneda: desde?.moneda ?? "ARS",
      alicuota: desde?.alicuota ?? 21,
      orden,
    },
  });
  const { errors } = formState;

  async function onSubmit(data: SeccionForm) {
    setEnviando(true);
    const result = await guardarSeccion(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(seccion ? "Sección guardada" : "Sección creada");
    onClose();
  }

  return (
    <RightPanel
      title={seccion ? "Editar sección" : "Nueva sección"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <PiePanel
          confirmar={seccion ? "Guardar" : "Crear sección"}
          enviando={enviando}
          onCancelar={onClose}
          form={FORM_ID}
          nota={seccion ? "Con otra moneda, sus ventanas se recalculan." : undefined}
        />
      }
    >
      <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
        <Campo id="sec-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="sec-nombre" aria-required placeholder="Ej: Colocación" className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="sec-moneda" label="Moneda" requerido error={errors.moneda}>
          <select id="sec-moneda" aria-required className={claseInput(errors.moneda)} {...register("moneda")}>
            {MONEDAS_LISTA.map((m) => (
              <option key={m} value={m}>
                {MONEDAS[m]}
              </option>
            ))}
          </select>
        </Campo>
        <Campo id="sec-alicuota" label="IVA" requerido error={errors.alicuota}>
          <select id="sec-alicuota" aria-required className={claseInput(errors.alicuota)} {...register("alicuota")}>
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
