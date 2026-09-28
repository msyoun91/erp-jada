"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { RightPanel } from "@/components/ui/RightPanel";
import { crearPersona, editarPersona, guardarEmpresa } from "../actions";
import {
  editarPersonaSchema,
  empresaSchema,
  personaSchema,
  type DatosContacto,
  type EditarPersonaForm,
  type Empresa,
  type EmpresaForm,
  type Persona,
  type PersonaForm,
} from "../types";
import { AvisoParecidas, useParecidas } from "./Parecidas";

const FORM_ID = "contacto-form";

function Pie({ enviando, crear, onClose }: { enviando: boolean; crear: string | null; onClose: () => void }) {
  return (
    <>
      <div className="flex-1" />
      <button type="button" className="btn btn-secondary btn-sm" onClick={onClose} disabled={enviando}>
        Cancelar
      </button>
      <button type="submit" form={FORM_ID} className="btn btn-primary btn-sm" disabled={enviando}>
        {enviando ? "Guardando…" : (crear ?? "Guardar")}
      </button>
    </>
  );
}

const claseForm = "flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-5 py-4";

export function NuevaPersonaPanel({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const { parecidas, revisar } = useParecidas();
  const { register, handleSubmit, formState } = useForm<PersonaForm>({
    resolver: zodResolver(personaSchema),
    defaultValues: { nombre: "", telefono: "", email: "", notas: "" },
  });
  const { errors } = formState;

  async function onSubmit(data: PersonaForm) {
    setEnviando(true);
    if (!(await revisar({ tipo: "persona", nombre: data.nombre, telefono: data.telefono, email: data.email }))) {
      setEnviando(false);
      return;
    }
    const result = await crearPersona(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(parecidas ? "Persona creada: espera aprobación" : "Persona creada");
    router.push(`/contactos/personas/${result.id}`);
    onClose();
  }

  return (
    <RightPanel title="Nueva persona" onClose={onClose} hayCambios={formState.isDirty} footer={<Pie enviando={enviando} crear={parecidas ? "Crear igual" : "Crear persona"} onClose={onClose} />}>
      <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className={claseForm}>
        <Campo id="p-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="p-nombre" aria-required placeholder="Marta Gómez" className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="p-telefono" label="Teléfono" error={errors.telefono}>
          <input id="p-telefono" type="tel" className={claseInput(errors.telefono)} {...register("telefono")} />
        </Campo>
        <Campo id="p-email" label="Email" error={errors.email}>
          <input id="p-email" type="email" className={claseInput(errors.email)} {...register("email")} />
        </Campo>
        <Campo id="p-notas" label="Notas" error={errors.notas}>
          <textarea id="p-notas" rows={3} className={claseInput(errors.notas)} {...register("notas")} />
        </Campo>
        {parecidas && <AvisoParecidas tipo="persona" items={parecidas} verbo="creala" />}
      </form>
    </RightPanel>
  );
}

// Teléfono y email se editan solo si quien edita los vio con "Ver contacto":
// si no, no los leyó y el formulario no los manda.
export function EditarPersonaPanel({
  persona,
  contacto,
  onClose,
}: {
  persona: Persona;
  contacto: DatosContacto | null;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { parecidas, revisar } = useParecidas();
  const { register, handleSubmit, formState } = useForm<EditarPersonaForm>({
    resolver: zodResolver(editarPersonaSchema),
    defaultValues: {
      id: persona.id,
      nombre: persona.nombre,
      notas: persona.notas ?? "",
      contacto: contacto ? { telefono: contacto.telefono ?? "", email: contacto.email ?? "" } : undefined,
    },
  });
  const { errors } = formState;

  async function onSubmit(data: EditarPersonaForm) {
    setEnviando(true);
    const compara =
      data.nombre !== persona.nombre ||
      (data.contacto && (data.contacto.telefono !== contacto?.telefono || data.contacto.email !== contacto?.email));
    const datos = { tipo: "persona" as const, id: persona.id, nombre: data.nombre, ...data.contacto };
    if (compara && !(await revisar(datos))) {
      setEnviando(false);
      return;
    }
    const result = await editarPersona(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Persona guardada");
    onClose();
  }

  return (
    <RightPanel
      title="Editar persona"
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={<Pie enviando={enviando} crear={parecidas ? "Guardar igual" : null} onClose={onClose} />}
    >
      <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className={claseForm}>
        <Campo id="p-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="p-nombre" aria-required className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        {contacto ? (
          <>
            <Campo id="p-telefono" label="Teléfono" error={errors.contacto?.telefono}>
              <input id="p-telefono" type="tel" className={claseInput(errors.contacto?.telefono)} {...register("contacto.telefono")} />
            </Campo>
            <Campo id="p-email" label="Email" error={errors.contacto?.email}>
              <input id="p-email" type="email" className={claseInput(errors.contacto?.email)} {...register("contacto.email")} />
            </Campo>
          </>
        ) : (
          <p className="t-caption">Para corregir teléfono o email, tocá antes «Ver contacto».</p>
        )}
        <Campo id="p-notas" label="Notas" error={errors.notas}>
          <textarea id="p-notas" rows={3} className={claseInput(errors.notas)} {...register("notas")} />
        </Campo>
        {parecidas && <AvisoParecidas tipo="persona" items={parecidas} verbo="guardala" />}
      </form>
    </RightPanel>
  );
}

export function EmpresaFormPanel({ empresa, onClose }: { empresa?: Empresa; onClose: () => void }) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const { parecidas, revisar } = useParecidas();
  const { register, handleSubmit, formState } = useForm<EmpresaForm>({
    resolver: zodResolver(empresaSchema),
    defaultValues: {
      id: empresa?.id,
      nombre: empresa?.nombre ?? "",
      telefono: empresa?.telefono ?? "",
      email: empresa?.email ?? "",
      web: empresa?.web ?? "",
      notas: empresa?.notas ?? "",
    },
  });
  const { errors } = formState;

  async function onSubmit(data: EmpresaForm) {
    setEnviando(true);
    const compara = data.nombre !== empresa?.nombre;
    if (compara && !(await revisar({ tipo: "empresa", id: empresa?.id, nombre: data.nombre }))) {
      setEnviando(false);
      return;
    }
    const result = await guardarEmpresa(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success(`${empresa ? "Empresa guardada" : "Empresa creada"}${parecidas ? ": espera aprobación" : ""}`);
    if ("id" in result) router.push(`/contactos/empresas/${result.id}`);
    onClose();
  }

  return (
    <RightPanel
      title={empresa ? "Editar empresa" : "Nueva empresa"}
      onClose={onClose}
      hayCambios={formState.isDirty}
      footer={
        <Pie enviando={enviando} crear={parecidas ? (empresa ? "Guardar igual" : "Crear igual") : empresa ? null : "Crear empresa"} onClose={onClose} />
      }
    >
      <form id={FORM_ID} onSubmit={handleSubmit(onSubmit)} className={claseForm}>
        <Campo id="e-nombre" label="Nombre" requerido error={errors.nombre}>
          <input id="e-nombre" aria-required placeholder="Constructora Sur" className={claseInput(errors.nombre)} {...register("nombre")} />
        </Campo>
        <Campo id="e-telefono" label="Teléfono" error={errors.telefono}>
          <input id="e-telefono" type="tel" className={claseInput(errors.telefono)} {...register("telefono")} />
        </Campo>
        <Campo id="e-email" label="Email" error={errors.email}>
          <input id="e-email" type="email" className={claseInput(errors.email)} {...register("email")} />
        </Campo>
        <Campo id="e-web" label="Web" error={errors.web}>
          <input id="e-web" className={claseInput(errors.web)} {...register("web")} />
        </Campo>
        <Campo id="e-notas" label="Notas" error={errors.notas}>
          <textarea id="e-notas" rows={3} className={claseInput(errors.notas)} {...register("notas")} />
        </Campo>
        {parecidas && <AvisoParecidas tipo="empresa" items={parecidas} verbo={empresa ? "guardala" : "creala"} />}
      </form>
    </RightPanel>
  );
}
