"use client";

import { useState } from "react";
import Link from "next/link";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, ArchiveRestore, CalendarX, Globe, Mail, Pencil, Phone, Plus, UsersRound } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { formatFecha } from "@/lib/utils";
import {
  asignarEquipoEmpresa,
  cerrarPersonaEmpresa,
  desactivarEmpresa,
  desactivarPersonaEmpresa,
  reactivarEmpresa,
  sumarEmpresa,
} from "../actions";
import type { EmpleadoConNombre, EmpresaCompleta } from "../queries";
import {
  equipoEmpresaSchema,
  personaEmpresaSchema,
  type EquipoEmpresaForm,
  type PersonaEmpresaForm,
  type Vinculable,
} from "../types";
import { BuscadorVinculables, IconoContacto } from "./Buscador";
import { EmpresaFormPanel } from "./ContactoFormPanel";
import { HistorialEdiciones, VinculosDeContacto, nombreDe } from "./FichaPartes";
import { EsperaAprobacion } from "./Parecidas";
import { CerrarModal } from "./VinculosSeccion";

type Dialogo = "editar" | "desactivar" | "sumar" | "equipo";
type DialogoRelacion = { tipo: "cerrar" | "desactivar"; relacion: EmpleadoConNombre };

type Props = EmpresaCompleta & {
  yo: string;
  admin: boolean;
  // Desactiva el delegador de su equipo, quien la cargó (sin equipo) o el admin (CO007).
  desactiva: boolean;
  nombres: Record<string, string>;
  // A cuál puede pasarla el admin (CO008); vacío para el resto.
  equipos: { id: string; nombre: string }[];
};

export function EmpresaView({ empresa, personas, vinculos, ediciones, yo, admin, desactiva, nombres, equipos }: Props) {
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);
  const [relacion, setRelacion] = useState<DialogoRelacion | null>(null);
  const nombre = (id: string | null) => nombreDe(nombres, id, yo);

  async function correr(accion: (id: string) => Promise<{ success: boolean; error?: string }>, ok: string) {
    const r = await accion(empresa.id);
    if (!r.success) toast.error(r.error);
    else toast.success(ok);
  }

  const menu = [
    ...(empresa.activo ? [{ label: "Editar", icon: <Pencil size={14} />, onClick: () => setDialogo("editar") }] : []),
    ...(admin && empresa.activo && equipos.length > 0
      ? [{ label: empresa.equipo_id ? "Cambiar equipo" : "Asignar equipo", icon: <UsersRound size={14} />, onClick: () => setDialogo("equipo") }]
      : []),
    ...(desactiva && empresa.activo
      ? [{ label: "Desactivar", icon: <Archive size={14} />, onClick: () => setDialogo("desactivar"), destructive: true }]
      : []),
    ...(admin && !empresa.activo
      ? [{ label: "Reactivar", icon: <ArchiveRestore size={14} />, onClick: () => correr(reactivarEmpresa, "Empresa reactivada") }]
      : []),
  ];

  const actuales = personas.filter((p) => p.hasta === null);
  const anteriores = personas.filter((p) => p.hasta !== null);

  function filaPersona(r: EmpleadoConNombre) {
    const p = r.contactos_personas;
    const dueno = admin || p?.responsable_id === yo;
    return (
      <li key={r.id} className="row flex items-center gap-3 border-b border-border last:border-b-0">
        <IconoContacto tipo="persona" />
        <div className="min-w-0 flex-1">
          {p && (
            <Link href={`/contactos/personas/${p.id}`} className="t-body-m block truncate font-medium text-text-primary hover:underline">
              {p.nombre}
            </Link>
          )}
          <p className="t-caption flex flex-wrap gap-x-3">
            {r.cargo && <span>{r.cargo}</span>}
            <span>{r.hasta ? `${formatFecha(r.desde)} – ${formatFecha(r.hasta)}` : `Desde ${formatFecha(r.desde)}`}</span>
          </p>
        </div>
        {dueno && r.hasta === null && (
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
          <IconoContacto tipo="empresa" />
          <h2 className="t-h2 min-w-0 flex-1">{empresa.nombre}</h2>
          {!empresa.activo && <span className="badge badge-neutral">Desactivada</span>}
          {menu.length > 0 && <OverflowMenu items={menu} />}
        </div>
        <p className="t-caption flex items-center gap-1" title="Equipo">
          <UsersRound size={12} strokeWidth={1.75} />
          {empresa.equipo_id ? (nombres[empresa.equipo_id] ?? "—") : `Sin equipo · la cargó ${nombre(empresa.creado_por)}`}
        </p>
        {empresa.activo && empresa.congelada && <EsperaAprobacion tipo="empresa" />}
        <div className="flex flex-col gap-1">
          {empresa.telefono && (
            <a href={`tel:${empresa.telefono}`} className="t-body-m flex items-center gap-2 text-text-brand">
              <Phone size={14} strokeWidth={1.75} />
              {empresa.telefono}
            </a>
          )}
          {empresa.email && (
            <a href={`mailto:${empresa.email}`} className="t-body-m flex items-center gap-2 text-text-brand">
              <Mail size={14} strokeWidth={1.75} />
              {empresa.email}
            </a>
          )}
          {empresa.web && (
            <p className="t-body-m flex items-center gap-2">
              <Globe size={14} strokeWidth={1.75} />
              {empresa.web}
            </p>
          )}
        </div>
        {empresa.notas && <p className="t-body-m whitespace-pre-wrap">{empresa.notas}</p>}
      </div>

      <div>
        <div className="mb-2 flex items-center">
          <p className="t-label flex-1">Personas</p>
          {empresa.activo && (
            <button className="btn btn-secondary btn-sm" onClick={() => setDialogo("sumar")}>
              <Plus size={14} />
              Sumar persona
            </button>
          )}
        </div>
        {actuales.length === 0 ? (
          <div className="empty-state">
            <p className="t-body-m">Sin personas que veas.</p>
          </div>
        ) : (
          <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">{actuales.map(filaPersona)}</ul>
        )}
        {anteriores.length > 0 && (
          <details className="mt-2">
            <summary className="t-label cursor-pointer py-2">Anteriores ({anteriores.length})</summary>
            <ul className="flex flex-col rounded-lg border border-border bg-bg-subtle">{anteriores.map(filaPersona)}</ul>
          </details>
        )}
      </div>

      <VinculosDeContacto vinculos={vinculos} />

      <div className="card">
        <HistorialEdiciones ediciones={ediciones} nombre={nombre} />
      </div>

      {dialogo === "editar" && <EmpresaFormPanel empresa={empresa} onClose={() => setDialogo(null)} />}
      {dialogo === "equipo" && (
        <EquipoModal empresaId={empresa.id} actual={empresa.equipo_id} equipos={equipos} onClose={() => setDialogo(null)} />
      )}
      {dialogo === "sumar" && <SumarPersonaModal empresaId={empresa.id} onClose={() => setDialogo(null)} />}
      {dialogo === "desactivar" && (
        <ConfirmModal
          title="Desactivar empresa"
          mensaje={`¿Desactivar ${empresa.nombre}? Deja de aparecer en el equipo; en las obras donde figura queda como inactiva.`}
          onConfirm={() => correr(desactivarEmpresa, "Empresa desactivada")}
          onClose={() => setDialogo(null)}
        />
      )}
      {relacion?.tipo === "cerrar" && (
        <CerrarModal
          id={relacion.relacion.id}
          titulo="Ya no trabaja acá"
          explicacion="La persona pasa a «Anteriores» desde esa fecha. Si vuelve, se suma de nuevo."
          accion={cerrarPersonaEmpresa}
          onClose={() => setRelacion(null)}
        />
      )}
      {relacion?.tipo === "desactivar" && (
        <ConfirmModal
          title="Cargado por error"
          mensaje="¿Sacar a esta persona? Es para una relación que no tendría que existir: si trabajó acá y ya no, usá «Cerrar»."
          confirmLabel="Sacar"
          onConfirm={async () => {
            const r = await desactivarPersonaEmpresa(relacion.relacion.id);
            if (!r.success) toast.error(r.error);
            else toast.success("Persona sacada");
          }}
          onClose={() => setRelacion(null)}
        />
      )}
    </div>
  );
}

// Una de tus personas (la relación la suma su dueño, CO012). Crear una desde
// acá queda para después (BACKLOG → Contactos y Obras).
function SumarPersonaModal({ empresaId, onClose }: { empresaId: string; onClose: () => void }) {
  const [enviando, setEnviando] = useState(false);
  const [persona, setPersona] = useState<Vinculable | null>(null);
  const { register, handleSubmit, setValue, formState } = useForm<PersonaEmpresaForm>({
    resolver: zodResolver(personaEmpresaSchema),
    defaultValues: { persona_id: "", empresa_id: empresaId, cargo: "", desde: "" },
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
    toast.success("Persona sumada");
    onClose();
  }

  return (
    <FormModal
      title="Sumar persona"
      confirmLabel="Sumar"
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={persona !== null}
    >
      <div>
        <p className="t-label t-label-req mb-1">Persona</p>
        {persona ? (
          <div className="flex items-center gap-2 rounded-md border border-border px-3 py-2">
            <IconoContacto tipo="persona" />
            <span className="t-body-m min-w-0 flex-1 truncate">{persona.nombre}</span>
            <button
              type="button"
              className="btn btn-ghost btn-sm"
              onClick={() => {
                setPersona(null);
                setValue("persona_id", "");
              }}
            >
              Cambiar
            </button>
          </div>
        ) : (
          <BuscadorVinculables
            tipos={["persona"]}
            onElegir={(v) => {
              setPersona(v);
              setValue("persona_id", v.id);
            }}
          />
        )}
        {errors.persona_id && <p className="input-error-text">Elegí la persona</p>}
      </div>
      <Campo id="sp-cargo" label="Cargo" error={errors.cargo}>
        <input id="sp-cargo" placeholder="Capataz, compras…" className={claseInput(errors.cargo)} {...register("cargo")} />
      </Campo>
      <Campo id="sp-desde" label="Desde" error={errors.desde}>
        <input id="sp-desde" type="date" className={claseInput(errors.desde)} {...register("desde")} />
      </Campo>
    </FormModal>
  );
}

// La empresa pasa a ese equipo: la ven y la editan sus miembros, la desactiva
// su delegador. Es como el admin rescata una huérfana (sin equipo, cargadora sin vista).
function EquipoModal({
  empresaId,
  actual,
  equipos,
  onClose,
}: {
  empresaId: string;
  actual: string | null;
  equipos: { id: string; nombre: string }[];
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<EquipoEmpresaForm>({
    resolver: zodResolver(equipoEmpresaSchema),
    defaultValues: { id: empresaId, equipo_id: actual ?? "" },
  });

  async function onSubmit(data: EquipoEmpresaForm) {
    setEnviando(true);
    const r = await asignarEquipoEmpresa(data);
    setEnviando(false);
    if (!r.success) {
      toast.error(r.error);
      return;
    }
    toast.success("Equipo asignado");
    onClose();
  }

  return (
    <FormModal
      title={actual ? "Cambiar equipo" : "Asignar equipo"}
      confirmLabel="Guardar"
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      <p className="t-body-m">La ven y la editan los miembros del equipo; la desactiva su delegador.</p>
      <Campo id="ee-equipo" label="Equipo" requerido error={formState.errors.equipo_id}>
        <select id="ee-equipo" aria-required className={claseInput(formState.errors.equipo_id)} {...register("equipo_id")}>
          <option value="">Elegí el equipo</option>
          {equipos.map((e) => (
            <option key={e.id} value={e.id}>
              {e.nombre}
            </option>
          ))}
        </select>
      </Campo>
    </FormModal>
  );
}
