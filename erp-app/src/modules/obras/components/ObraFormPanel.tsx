"use client";

import { useState, type ComponentType } from "react";
import { useRouter } from "next/navigation";
import { FormProvider, useForm, useFormContext, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { ENTES } from "@/lib/entes";
import { crearObra, editarObra } from "../actions";
import { ORIGEN, TIPO } from "../etiquetas";
import { ESTADOS_ABIERTOS, LABEL_ESTADO, altaSchema, obraSchema, type AltaForm, type Obra, type ObraForm } from "../types";

// "¿Quién?" lo busca y lo crea Contactos; `app/` lo compone (GUIDE_ENTES §2.7).
export type Quien = { tipo: "persona" | "empresa"; id: string | null; nombre: string; telefono: string; email: string };
export type QuienSlot = ComponentType<{ valor: Quien | null; onCambio: (q: Quien | null) => void }>;

const FORM_ID = "obra-form";
const DATOS = ENTES.obra.datos;

// Lo que comparten el alta y la edición: los datos de la obra, del form que
// los envuelva.
type DatosObra = Omit<ObraForm, "id">;

function useDatos() {
  const { register, formState } = useFormContext<DatosObra>();
  return { register, errors: formState.errors };
}

function CamposObra() {
  const { register, errors } = useDatos();
  return (
    <>
      <Campo id="obra-nombre" label="Nombre" requerido error={errors.nombre}>
        <input id="obra-nombre" aria-required placeholder={DATOS.nombre.ejemplo} className={claseInput(errors.nombre)} {...register("nombre")} />
      </Campo>
      <Campo id="obra-direccion" label="Dirección" requerido error={errors.direccion}>
        <input id="obra-direccion" aria-required placeholder={DATOS.direccion.ejemplo} className={claseInput(errors.direccion)} {...register("direccion")} />
      </Campo>
      <Campo id="obra-localidad" label="Localidad" error={errors.localidad}>
        <input id="obra-localidad" placeholder={DATOS.localidad.ejemplo} className={claseInput(errors.localidad)} {...register("localidad")} />
      </Campo>
      <Campo id="obra-tipo" label="Tipo de obra" requerido error={errors.tipo}>
        <select id="obra-tipo" aria-required className={claseInput(errors.tipo)} {...register("tipo")}>
          <option value="">Elegí el tipo</option>
          {Object.entries(TIPO).map(([valor, label]) => (
            <option key={valor} value={valor}>
              {label}
            </option>
          ))}
        </select>
      </Campo>
      <Campo id="obra-compra" label="Compra estimada" error={errors.compra_estimada}>
        <input id="obra-compra" type="month" className={claseInput(errors.compra_estimada)} {...register("compra_estimada")} />
      </Campo>
    </>
  );
}

function CampoOrigen() {
  const { register, errors } = useDatos();
  return (
    <Campo id="obra-origen" label="Origen" requerido error={errors.origen}>
      <select id="obra-origen" aria-required className={claseInput(errors.origen)} {...register("origen")}>
        <option value="">¿Cómo llegó?</option>
        {Object.entries(ORIGEN).map(([valor, label]) => (
          <option key={valor} value={valor}>
            {label}
          </option>
        ))}
      </select>
    </Campo>
  );
}

function CampoNotas() {
  const { register, errors } = useDatos();
  return (
    <Campo id="obra-notas" label="Notas" error={errors.notas}>
      <textarea id="obra-notas" rows={3} className={claseInput(errors.notas)} {...register("notas")} />
    </Campo>
  );
}

function Pie({ enviando, confirmar, onClose }: { enviando: boolean; confirmar: string; onClose: () => void }) {
  return (
    <>
      <div className="flex-1" />
      <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
        Cancelar
      </button>
      <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
        {enviando ? "Guardando…" : confirmar}
      </button>
    </>
  );
}

const claseForm = "flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4";

export function AltaObraPanel({ Quien, onClose }: { Quien: QuienSlot; onClose: () => void }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [quien, setQuien] = useState<Quien | null>(null);
  const form = useForm<AltaForm>({
    resolver: zodResolver(altaSchema),
    defaultValues: {
      nombre: "",
      direccion: "",
      localidad: "",
      notas: "",
      compra_estimada: "",
      estado: "idea",
    },
  });
  const { register, handleSubmit, setValue, control, formState } = form;
  const { errors } = formState;
  const conReferente = useWatch({ control, name: "origen" }) === "referente";
  const errorQuien = errors.quien_persona ?? errors.quien_nuevo_nombre ?? errors.quien_nuevo_telefono ?? errors.quien_nuevo_email;

  async function onSubmit(data: AltaForm) {
    setEnviando(true);
    const result = await crearObra(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Obra creada");
    router.push(`/obras/${result.id}`);
    onClose();
  }

  // "¿Quién?" vive fuera del form (lo dibuja Contactos): se copia al enviar.
  function copiarQuien() {
    const q = conReferente ? quien : null;
    setValue("quien_persona", q?.id && q.tipo === "persona" ? q.id : null);
    setValue("quien_empresa", q?.id && q.tipo === "empresa" ? q.id : null);
    setValue("quien_nuevo_tipo", q && !q.id ? q.tipo : null);
    setValue("quien_nuevo_nombre", q && !q.id ? q.nombre : null);
    setValue("quien_nuevo_telefono", q && !q.id ? q.telefono : null);
    setValue("quien_nuevo_email", q && !q.id ? q.email : null);
  }

  return (
    <RightPanel
      title="Nueva obra"
      onClose={onClose}
      hayCambios={formState.isDirty || quien !== null}
      footer={<Pie enviando={enviando} confirmar="Crear obra" onClose={onClose} />}
    >
      <FormProvider {...form}>
        <form
          id={FORM_ID}
          onSubmit={(e) => {
            copiarQuien();
            return handleSubmit(onSubmit)(e);
          }}
          className={claseForm}
        >
          <CamposObra />
          <CampoOrigen />
          {conReferente && (
            <div>
              <p className="t-label mb-1">¿Quién?</p>
              <Quien valor={quien} onCambio={setQuien} />
              {errorQuien ? (
                <p className="input-error-text">{errorQuien.message}</p>
              ) : (
                <p className="t-caption mt-1">Queda vinculado a la obra como referente.</p>
              )}
            </div>
          )}
          <Campo id="obra-estado" label="Estado" requerido error={errors.estado}>
            <select id="obra-estado" aria-required className={claseInput(errors.estado)} {...register("estado")}>
              {ESTADOS_ABIERTOS.map((e) => (
                <option key={e} value={e}>
                  {LABEL_ESTADO[e].label}
                </option>
              ))}
            </select>
          </Campo>
          <CampoNotas />
        </form>
      </FormProvider>
    </RightPanel>
  );
}

export function EditarObraPanel({ obra, onClose }: { obra: Obra; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const form = useForm<ObraForm>({
    resolver: zodResolver(obraSchema),
    defaultValues: {
      id: obra.id,
      nombre: obra.nombre,
      direccion: obra.direccion,
      localidad: obra.localidad ?? "",
      notas: obra.notas ?? "",
      origen: obra.origen,
      tipo: obra.tipo,
      compra_estimada: obra.compra_estimada?.slice(0, 7) ?? "",
    },
  });
  const { handleSubmit, formState } = form;

  async function onSubmit(data: ObraForm) {
    setEnviando(true);
    const result = await editarObra(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Obra guardada");
    onClose();
  }

  return (
    <RightPanel
      title="Editar obra"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<Pie enviando={enviando} confirmar="Guardar" onClose={onClose} />}
    >
      <FormProvider {...form}>
        <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className={claseForm}>
          <CamposObra />
          <CampoOrigen />
          <CampoNotas />
        </form>
      </FormProvider>
    </RightPanel>
  );
}
