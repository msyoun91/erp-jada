"use client";

import { useState, type ComponentType } from "react";
import { flushSync } from "react-dom";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { PiePanel, RightPanel } from "@/components/ui/RightPanel";
import { formatMonto, MONEDAS, MONEDAS_LISTA } from "@/lib/monedas";
import { crearPresupuesto } from "../actions";
import { ALICUOTAS, altaSchema, formatAlicuota, type AltaForm, type VentanaForm } from "../types";

const FORM_ID = "presupuesto-alta-form";

type ObraElegible = { id: string; nombre: string };

// El alta de Obras, que compone `app/`: al crear, vuelve con la obra en lugar de ir a su ficha.
export type NuevaObraSlot = ComponentType<{ onCreada: (obra: ObraElegible) => void; onClose: () => void }>;

// La de la calculadora de venta, ya calculada: `nombre` es el del paquete y `detalle`, lo cargado.
export type VentanaLlevada = VentanaForm & { nombre: string; detalle: string | null; precio: number };

// Con una sola obra (la ficha de la obra), va puesta y no se elige.
export function AltaPresupuestoPanel({
  obras,
  ventana,
  NuevaObra,
  onClose,
}: {
  obras: ObraElegible[];
  ventana?: VentanaLlevada;
  NuevaObra?: NuevaObraSlot;
  onClose: () => void;
}) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [lista, setLista] = useState(obras);
  const [creandoObra, setCreandoObra] = useState(false);
  const fija = lista.length === 1 ? lista[0] : null;
  const { register, handleSubmit, formState, control, setValue } = useForm<AltaForm>({
    resolver: zodResolver(altaSchema),
    defaultValues: { obra: fija?.id ?? "", nombre: "", moneda: ventana?.moneda ?? "ARS", alicuota: 21, seccion: "" },
  });
  const { errors } = formState;
  const moneda = useWatch({ control, name: "moneda" });

  async function onSubmit(data: AltaForm) {
    setEnviando(true);
    const result = await crearPresupuesto({
      ...data,
      ventana: ventana && { paquete_id: ventana.paquete_id, entrada: ventana.entrada, opcionales: ventana.opcionales },
    });
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Presupuesto creado");
    router.push(result.version ? `/presupuestos/${result.id}/${result.version}` : `/presupuestos/${result.id}`);
    onClose();
  }

  // La opción tiene que estar en el select antes de elegirla: si no, el select queda en "Elegí la obra" aunque el form la tenga.
  function obraCreada(obra: ObraElegible) {
    flushSync(() => setLista((l) => [...l, obra].sort((a, b) => a.nombre.localeCompare(b.nombre))));
    setValue("obra", obra.id, { shouldDirty: true, shouldValidate: true });
  }

  return (
    <>
      <RightPanel
        title="Nuevo presupuesto"
        onClose={onClose}
        hayCambios={formState.isDirty}
        footer={<PiePanel confirmar="Crear presupuesto" enviando={enviando} onCancelar={onClose} form={FORM_ID} />}
      >
        <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4">
          {ventana && (
            <div className="rounded-lg border border-border bg-bg-subtle px-3 py-2">
              <p className="t-body-m font-medium text-text-primary">{ventana.nombre}</p>
              {ventana.detalle && <p className="t-caption">{ventana.detalle}</p>}
              <p className="t-body-m mt-1">{formatMonto(ventana.precio, ventana.moneda)} sin IVA · cantidad 1</p>
              {moneda !== ventana.moneda && <p className="t-caption">En el presupuesto, se calcula en {MONEDAS[moneda]}.</p>}
            </div>
          )}
          <Campo id="pres-obra" label="Obra" requerido error={errors.obra}>
            <div className="flex gap-2">
              {fija ? (
                <input id="pres-obra" className="input min-w-0 flex-1" value={fija.nombre} disabled />
              ) : (
                <select id="pres-obra" aria-required className={`${claseInput(errors.obra)} min-w-0 flex-1`} {...register("obra")}>
                  <option value="">Elegí la obra</option>
                  {lista.map((o) => (
                    <option key={o.id} value={o.id}>
                      {o.nombre}
                    </option>
                  ))}
                </select>
              )}
              {NuevaObra && (
                <button type="button" className="btn btn-secondary shrink-0" onClick={() => setCreandoObra(true)}>
                  <Plus size={16} />
                  Nueva obra
                </button>
              )}
            </div>
          </Campo>
          <Campo id="pres-nombre" label="Nombre" requerido error={errors.nombre}>
            <input id="pres-nombre" aria-required placeholder="Ej: Aberturas planta baja" className={claseInput(errors.nombre)} {...register("nombre")} />
          </Campo>
          <Campo id="pres-moneda" label="Moneda de la primera sección" requerido error={errors.moneda}>
            <select id="pres-moneda" aria-required className={claseInput(errors.moneda)} {...register("moneda")}>
              {MONEDAS_LISTA.map((m) => (
                <option key={m} value={m}>
                  {MONEDAS[m]}
                </option>
              ))}
            </select>
          </Campo>
          <Campo id="pres-alicuota" label="IVA de la primera sección" requerido error={errors.alicuota}>
            <select id="pres-alicuota" aria-required className={claseInput(errors.alicuota)} {...register("alicuota")}>
              {ALICUOTAS.map((a) => (
                <option key={a} value={a}>
                  {formatAlicuota(a)}
                </option>
              ))}
            </select>
          </Campo>
          <Campo id="pres-seccion" label="Nombre de la sección" error={errors.seccion}>
            <input id="pres-seccion" placeholder="General" className={claseInput(errors.seccion)} {...register("seccion")} />
          </Campo>
        </form>
      </RightPanel>
      {/* Fuera del <form>: el alta de Obras tiene el suyo. */}
      {creandoObra && NuevaObra && <NuevaObra onCreada={obraCreada} onClose={() => setCreandoObra(false)} />}
    </>
  );
}
