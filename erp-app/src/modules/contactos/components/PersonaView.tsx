"use client";

import { useState } from "react";
import Link from "next/link";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, ArchiveRestore, ArrowLeftRight, CalendarX, Eye, Mail, Pencil, Phone, Plus, UserRound } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import type { UsuarioBasico } from "@/lib/usuarios";
import { formatFecha } from "@/lib/utils";
import {
  cerrarPersonaEmpresa,
  desactivarPersona,
  desactivarPersonaEmpresa,
  reactivarPersona,
  sumarEmpresa,
  transferirPersona,
  verContacto,
} from "../actions";
import type { PersonaCompleta, PersonaEmpresaConNombre } from "../queries";
import {
  personaEmpresaSchema,
  transferirPersonaSchema,
  type DatosContacto,
  type PersonaEmpresaForm,
  type TransferirPersonaForm,
} from "../types";
import { EmpresaSelector, IconoContacto, type EmpresaElegida } from "./Buscador";
import { EditarPersonaPanel } from "./ContactoFormPanel";
import { HistorialEdiciones, VinculosDeContacto, nombreDe } from "./FichaPartes";
import { CerrarModal } from "./VinculosSeccion";

type Dialogo = "editar" | "transferir" | "desactivar" | "sumar";
type DialogoRelacion = { tipo: "cerrar" | "desactivar"; relacion: PersonaEmpresaConNombre };

type Props = PersonaCompleta & {
  yo: string;
  admin: boolean;
  nombres: Record<string, string>;
  candidatos: UsuarioBasico[];
};

export function PersonaView({ persona, empresas, vinculos, ediciones, yo, admin, nombres, candidatos }: Props) {
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const [relacion, setRelacion] = useState<DialogoRelacion | null>(null);
  const [contacto, setContacto] = useState<DatosContacto | null>(null);
  const [viendo, setViendo] = useState(false);
  const nombre = (id: string | null) => nombreDe(nombres, id, yo);

  const dueno = persona.responsable_id === yo || admin;
  // Corrige también quien trabaja una obra donde figura; la base lo confirma (CO001).
  const edita = persona.activo && (dueno || vinculos.some((v) => v.hasta === null && v.href !== null));

  async function onVerContacto() {
    setViendo(true);
    const r = await verContacto(persona.id);
    setViendo(false);
    if (!r.success) toast.error(r.error);
    else setContacto(r.contacto);
  }

  async function correr(accion: (id: string) => Promise<{ success: boolean; error?: string }>, ok: string) {
    const r = await accion(persona.id);
    if (!r.success) toast.error(r.error);
    else toast.success(ok);
  }

  const menu = [
    ...(edita ? [{ label: "Editar", icon: <Pencil size={14} />, onClick: () => setDialogo("editar") }] : []),
    ...(dueno && persona.activo
      ? [
          { label: "Transferir", icon: <ArrowLeftRight size={14} />, onClick: () => setDialogo("transferir") },
          { label: "Desactivar", icon: <Archive size={14} />, onClick: () => setDialogo("desactivar"), destructive: true },
        ]
      : []),
    ...(admin && !persona.activo
      ? [{ label: "Reactivar", icon: <ArchiveRestore size={14} />, onClick: () => correr(reactivarPersona, "Persona reactivada") }]
      : []),
  ];

  const abiertas = empresas.filter((e) => e.hasta === null);
  const anteriores = empresas.filter((e) => e.hasta !== null);

  function filaEmpresa(r: PersonaEmpresaConNombre) {
    const e = r.contactos_empresas;
    return (
      <li key={r.id} className="row flex items-center gap-3 border-b border-border last:border-b-0">
        <IconoContacto tipo="empresa" />
        <div className="min-w-0 flex-1">
          {e ? (
            <Link href={`/contactos/empresas/${e.id}`} className="t-body-m block truncate font-medium text-text-primary hover:underline">
              {e.nombre}
            </Link>
          ) : (
            <p className="t-body-m text-text-tertiary">Una empresa que no ves</p>
          )}
          <p className="t-caption flex flex-wrap gap-x-3">
            {r.cargo && <span>{r.cargo}</span>}
            <span>{r.hasta ? `${formatFecha(r.desde)} – ${formatFecha(r.hasta)}` : `Desde ${formatFecha(r.desde)}`}</span>
          </p>
        </div>
        {dueno && persona.activo && r.hasta === null && (
          <OverflowMenu
            items={[
              { label: "Cerrar", icon: <CalendarX size={14} />, onClick: () => setRelacion({ tipo: "cerrar", relacion: r }) },
              {
                label: "Cargado por error",
                icon: <Archive size={14} />,
                onClick: () => setRelacion({ tipo: "desactivar", relacion: r }),
                destructive: true,
              },
            ]}
          />
        )}
      </li>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="card flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <IconoContacto tipo="persona" />
          <h2 className="t-h2 min-w-0 flex-1">{persona.nombre}</h2>
          {!persona.activo && <span className="badge badge-neutral">Desactivada</span>}
          {menu.length > 0 && <OverflowMenu items={menu} />}
        </div>
        <p className="t-caption flex items-center gap-1" title="Dueño">
          <UserRound size={12} strokeWidth={1.75} />
          {nombre(persona.responsable_id)}
        </p>
        {contacto ? (
          <div className="flex flex-col gap-1">
            {contacto.telefono ? (
              <a href={`tel:${contacto.telefono}`} className="t-body-m flex items-center gap-2 text-text-brand">
                <Phone size={14} strokeWidth={1.75} />
                {contacto.telefono}
              </a>
            ) : (
              <p className="t-caption">Sin teléfono</p>
            )}
            {contacto.email ? (
              <a href={`mailto:${contacto.email}`} className="t-body-m flex items-center gap-2 text-text-brand">
                <Mail size={14} strokeWidth={1.75} />
                {contacto.email}
              </a>
            ) : (
              <p className="t-caption">Sin email</p>
            )}
          </div>
        ) : (
          <div>
            <button className="btn btn-secondary btn-sm" onClick={onVerContacto} disabled={viendo}>
              <Eye size={14} />
              {viendo ? "Buscando…" : "Ver contacto"}
            </button>
            <p className="t-caption mt-1">Queda registrado quién lo miró.</p>
          </div>
        )}
        {persona.notas && <p className="t-body-m whitespace-pre-wrap">{persona.notas}</p>}
      </div>

      <div>
        <div className="mb-2 flex items-center">
          <p className="t-label flex-1">Empresas</p>
          {dueno && persona.activo && (
            <button className="btn btn-secondary btn-sm" onClick={() => setDialogo("sumar")}>
              <Plus size={14} />
              Sumar empresa
            </button>
          )}
        </div>
        {abiertas.length === 0 ? (
          <div className="empty-state">
            <p className="t-body-m">Sin empresa.</p>
          </div>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">{abiertas.map(filaEmpresa)}</ul>
        )}
        {anteriores.length > 0 && (
          <details className="mt-2">
            <summary className="t-label cursor-pointer py-2">Anteriores ({anteriores.length})</summary>
            <ul className="flex flex-col rounded-lg border border-border bg-bg-subtle">{anteriores.map(filaEmpresa)}</ul>
          </details>
        )}
      </div>

      <VinculosDeContacto vinculos={vinculos} />

      <div className="card">
        <HistorialEdiciones ediciones={ediciones} nombre={nombre} personaId={persona.id} />
      </div>

      {dialogo === "editar" && <EditarPersonaPanel persona={persona} contacto={contacto} onClose={() => setDialogo(null)} />}
      {dialogo === "transferir" && (
        <TransferirModal
          personaId={persona.id}
          candidatos={candidatos.filter((c) => c.id !== persona.responsable_id)}
          onClose={() => setDialogo(null)}
        />
      )}
      {dialogo === "sumar" && <SumarEmpresaModal personaId={persona.id} onClose={() => setDialogo(null)} />}
      {dialogo === "desactivar" && (
        <ConfirmModal
          title="Desactivar persona"
          mensaje={`¿Desactivar a ${persona.nombre}? Sale de tu agenda; en las obras donde figura queda como inactiva.`}
          onConfirm={() => correr(desactivarPersona, "Persona desactivada")}
          onClose={() => setDialogo(null)}
        />
      )}
      {relacion?.tipo === "cerrar" && (
        <CerrarModal
          id={relacion.relacion.id}
          titulo="Ya no trabaja ahí"
          explicacion="La empresa pasa a «Anteriores» desde esa fecha. Si vuelve, se suma de nuevo."
          accion={cerrarPersonaEmpresa}
          onClose={() => setRelacion(null)}
        />
      )}
      {relacion?.tipo === "desactivar" && (
        <ConfirmModal
          title="Cargado por error"
          mensaje="¿Sacar esta empresa? Es para una relación que no tendría que existir: si trabajó ahí y ya no, usá «Cerrar»."
          confirmLabel="Sacar"
          onConfirm={async () => {
            const r = await desactivarPersonaEmpresa(relacion.relacion.id);
            if (!r.success) toast.error(r.error);
            else toast.success("Empresa sacada");
          }}
          onClose={() => setRelacion(null)}
        />
      )}
    </div>
  );
}

function TransferirModal({
  personaId,
  candidatos,
  onClose,
}: {
  personaId: string;
  candidatos: UsuarioBasico[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<TransferirPersonaForm>({
    resolver: zodResolver(transferirPersonaSchema),
    defaultValues: { id: personaId, responsable_id: "" },
  });

  async function onSubmit(data: TransferirPersonaForm) {
    setEnviando(true);
    const r = await transferirPersona(data);
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success("Persona transferida");
    onClose();
  }

  return (
    <FormModal title="Transferir persona" confirmLabel="Transferir" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      <p className="t-body-m">Pasa a la agenda de quien elijas. Vos la seguís viendo solo si figura en algo que ves.</p>
      <Campo id="tp-a" label="Nuevo dueño" requerido error={formState.errors.responsable_id}>
        <select id="tp-a" aria-required className={claseInput(formState.errors.responsable_id)} {...register("responsable_id")}>
          <option value="">Elegí a quién</option>
          {candidatos.map((c) => (
            <option key={c.id} value={c.id}>
              {c.nombre}
            </option>
          ))}
        </select>
      </Campo>
    </FormModal>
  );
}

// Una empresa que ya se ve. Crear una desde acá queda para después
// (BACKLOG → Contactos y Obras).
function SumarEmpresaModal({ personaId, onClose }: { personaId: string; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const [empresa, setEmpresa] = useState<EmpresaElegida | null>(null);
  const { register, handleSubmit, setValue, formState } = useForm<PersonaEmpresaForm>({
    resolver: zodResolver(personaEmpresaSchema),
    defaultValues: { persona_id: personaId, empresa_id: "", cargo: "", desde: "" },
  });
  const { errors } = formState;

  async function onSubmit(data: PersonaEmpresaForm) {
    setEnviando(true);
    const r = await sumarEmpresa(data);
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success("Empresa sumada");
    onClose();
  }

  return (
    <FormModal
      title="Sumar empresa"
      confirmLabel="Sumar"
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={empresa !== null}
    >
      <div>
        <p className="t-label t-label-req mb-1">Empresa</p>
        <EmpresaSelector
          valor={empresa}
          onCambio={(e) => {
            setEmpresa(e);
            setValue("empresa_id", e?.id ?? "");
          }}
        />
        {errors.empresa_id && <p className="input-error-text">Elegí la empresa</p>}
      </div>
      <Campo id="se-cargo" label="Cargo" error={errors.cargo}>
        <input id="se-cargo" placeholder="Capataz, compras…" className={claseInput(errors.cargo)} {...register("cargo")} />
      </Campo>
      <Campo id="se-desde" label="Desde" error={errors.desde}>
        <input id="se-desde" type="date" className={claseInput(errors.desde)} {...register("desde")} />
      </Campo>
    </FormModal>
  );
}
