"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useForm, useWatch } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Archive, CalendarX, Plus, Tags } from "lucide-react";
import { toast } from "sonner";
import { Campo, claseInput } from "@/components/ui/Campo";
import { FormModal } from "@/components/ui/FormModal";
import { ConfirmModal } from "@/components/ui/Modal";
import { OverflowMenu } from "@/components/ui/OverflowMenu";
import { labelRol } from "@/lib/entes";
import { formatFecha, hoyISO, urlSin } from "@/lib/utils";
import { cambiarRoles, cerrarVinculo, desactivarVinculo } from "../actions";
import type { VinculoDeRegistro } from "../queries";
import { cerrarSchema, rolesSchema, type CerrarForm, type RolesForm } from "../types";
import { IconoContacto } from "./Buscador";
import { RolesCheck } from "./RolesCheck";
import { VincularPanel } from "./VincularPanel";

type Dialogo = { tipo: "roles" | "cerrar" | "desactivar"; vinculo: VinculoDeRegistro };

// Lo que otro módulo suma a un vínculo, por id (la comisión de Obras): se ve
// en la fila, y `aviso` se lee antes de cerrarlo, sacarlo o cambiarle el rol.
export type ExtraVinculo = { detalle: React.ReactNode; aviso?: string };

function contacto(v: VinculoDeRegistro) {
  const p = v.contactos_personas;
  const e = v.contactos_empresas;
  return p
    ? { tipo: "persona" as const, nombre: p.nombre, activo: p.activo, href: `/contactos/personas/${p.id}` }
    : { tipo: "empresa" as const, nombre: e?.nombre ?? "—", activo: e?.activo ?? true, href: e ? `/contactos/empresas/${e.id}` : null };
}

// Los contactos de un registro de otro módulo, compuesta en su ficha desde
// `app/` (GUIDE_ENTES §2.7). Vincular, cambiar el rol, cerrar y desactivar son
// de quien trabaja el registro (`trabaja`); la base lo vuelve a preguntar.
// `?vincular={rol}` (link de acción de Tareas) abre el panel con ese rol.
export function VinculosSeccion({
  ente,
  registroId,
  vinculos,
  trabaja,
  vincular,
  extras = {},
}: {
  ente: string;
  registroId: string;
  vinculos: VinculoDeRegistro[];
  trabaja: boolean;
  vincular: string | null;
  extras?: Record<string, ExtraVinculo>;
}) {
  const router = useRouter();
  const [panel, setPanel] = useState<{ rol: string | null } | null>(trabaja && vincular !== null ? { rol: vincular || null } : null);
  const [dialogo, setDialogo] = useState<Dialogo | null>(null);

  const abiertos = vinculos.filter((v) => v.hasta === null);
  const cerrados = vinculos.filter((v) => v.hasta !== null);
  const empresasDelRegistro = abiertos.flatMap((v) => (v.contactos_empresas ? [v.contactos_empresas] : []));

  function cerrarPanel() {
    setPanel(null);
    if (vincular !== null) router.replace(urlSin("vincular"), { scroll: false });
  }

  function fila(v: VinculoDeRegistro) {
    const c = contacto(v);
    const menu =
      trabaja && v.hasta === null
        ? [
            { label: "Cambiar rol", icon: <Tags size={14} />, onClick: () => setDialogo({ tipo: "roles", vinculo: v }) },
            { label: "Cerrar", icon: <CalendarX size={14} />, onClick: () => setDialogo({ tipo: "cerrar", vinculo: v }) },
            {
              label: "Cargado por error",
              icon: <Archive size={14} />,
              onClick: () => setDialogo({ tipo: "desactivar", vinculo: v }),
              destructive: true,
            },
          ]
        : [];
    return (
      <li key={v.id} className="row flex items-center gap-3 border-b border-border last:border-b-0">
        <IconoContacto tipo={c.tipo} />
        <div className="min-w-0 flex-1">
          {c.href ? (
            <Link href={c.href} className="t-body-m block truncate font-medium text-text-primary hover:underline">
              {c.nombre}
            </Link>
          ) : (
            <p className="t-body-m truncate font-medium">{c.nombre}</p>
          )}
          <p className="t-caption flex flex-wrap gap-x-3">
            <span>{v.roles.map((r) => labelRol(ente, r)).join(" · ")}</span>
            <span>
              {v.hasta ? `${formatFecha(v.desde)} – ${formatFecha(v.hasta)}` : `Desde ${formatFecha(v.desde)}`}
            </span>
          </p>
          {extras[v.id]?.detalle}
        </div>
        {!c.activo && <span className="badge badge-neutral">Inactivo</span>}
        {menu.length > 0 && <OverflowMenu items={menu} />}
      </li>
    );
  }

  return (
    <div>
      <div className="mb-2 flex items-center">
        <p className="t-label flex-1">Contactos</p>
        {trabaja && (
          <button className="btn btn-secondary btn-sm" onClick={() => setPanel({ rol: null })}>
            <Plus size={14} />
            Vincular contacto
          </button>
        )}
      </div>
      {abiertos.length === 0 ? (
        <div className="empty-state">
          <p className="t-body-m">
            {trabaja ? "Sin contactos todavía. Sumá el primero con «Vincular contacto»." : "Sin contactos vinculados."}
          </p>
        </div>
      ) : (
        <ul className="flex flex-col rounded-lg border border-border bg-bg-surface">{abiertos.map(fila)}</ul>
      )}
      {cerrados.length > 0 && (
        <details className="mt-2">
          <summary className="t-label cursor-pointer py-2">Anteriores ({cerrados.length})</summary>
          <ul className="flex flex-col rounded-lg border border-border bg-bg-subtle">{cerrados.map(fila)}</ul>
        </details>
      )}

      {panel && (
        <VincularPanel
          ente={ente}
          registroId={registroId}
          rolInicial={panel.rol}
          empresasDelRegistro={empresasDelRegistro}
          onClose={cerrarPanel}
        />
      )}
      {dialogo?.tipo === "roles" && (
        <RolesModal ente={ente} vinculo={dialogo.vinculo} aviso={extras[dialogo.vinculo.id]?.aviso} onClose={() => setDialogo(null)} />
      )}
      {dialogo?.tipo === "cerrar" && (
        <CerrarModal
          id={dialogo.vinculo.id}
          titulo={`Cerrar vínculo de ${contacto(dialogo.vinculo).nombre}`}
          explicacion={[
            "Deja de figurar desde esa fecha y pasa a «Anteriores». Si vuelve, se vincula de nuevo.",
            extras[dialogo.vinculo.id]?.aviso,
          ]
            .filter(Boolean)
            .join(" ")}
          accion={cerrarVinculo}
          onClose={() => setDialogo(null)}
        />
      )}
      {dialogo?.tipo === "desactivar" && (
        <ConfirmModal
          title="Cargado por error"
          mensaje={`¿Sacar a ${contacto(dialogo.vinculo).nombre}? Es para un vínculo que no tendría que existir: si estuvo y ya no está, usá «Cerrar».${
            extras[dialogo.vinculo.id]?.aviso ? ` ${extras[dialogo.vinculo.id]?.aviso}` : ""
          }`}
          confirmLabel="Sacar"
          onConfirm={async () => {
            const result = await desactivarVinculo(dialogo.vinculo.id);
            if (!result.success) toast.error(result.error);
            else toast.success("Vínculo sacado");
          }}
          onClose={() => setDialogo(null)}
        />
      )}
    </div>
  );
}

function RolesModal({
  ente,
  vinculo,
  aviso,
  onClose,
}: {
  ente: string;
  vinculo: VinculoDeRegistro;
  aviso?: string;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { handleSubmit, setValue, control, formState } = useForm<RolesForm>({
    resolver: zodResolver(rolesSchema),
    defaultValues: { id: vinculo.id, roles: vinculo.roles },
  });
  const roles = useWatch({ control, name: "roles" });

  async function onSubmit(data: RolesForm) {
    setEnviando(true);
    const result = await cambiarRoles(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Rol cambiado");
    onClose();
  }

  return (
    <FormModal
      title={`Rol de ${contacto(vinculo).nombre}`}
      confirmLabel="Guardar"
      onClose={onClose}
      onSubmit={handleSubmit(onSubmit)}
      enviando={enviando}
      hayCambios={formState.isDirty}
    >
      <RolesCheck ente={ente} valor={roles} onCambio={(r) => setValue("roles", r, { shouldDirty: true })} />
      {formState.errors.roles && <p className="input-error-text">{formState.errors.roles.message}</p>}
      {aviso && vinculo.roles.some((r) => !roles.includes(r)) && <p className="t-body-m text-warning-text">{aviso}</p>}
    </FormModal>
  );
}

// Cerrar un período (`hasta`): el vínculo con el registro y el de persona ↔ empresa.
export function CerrarModal({
  id,
  titulo,
  explicacion,
  accion,
  onClose,
}: {
  id: string;
  titulo: string;
  explicacion: string;
  accion: (input: CerrarForm) => Promise<{ success: boolean; error?: string }>;
  onClose: () => void;
}) {
  const [enviando, setEnviando] = useState(false);
  const { register, handleSubmit, formState } = useForm<CerrarForm>({
    resolver: zodResolver(cerrarSchema),
    defaultValues: { id, hasta: hoyISO() },
  });

  async function onSubmit(data: CerrarForm) {
    setEnviando(true);
    const result = await accion(data);
    setEnviando(false);
    if (!result.success) {
      toast.error(result.error);
      return;
    }
    toast.success("Cerrado");
    onClose();
  }

  return (
    <FormModal title={titulo} confirmLabel="Cerrar" onClose={onClose} onSubmit={handleSubmit(onSubmit)} enviando={enviando}>
      <p className="t-body-m">{explicacion}</p>
      <Campo id="cerrar-hasta" label="Hasta" requerido error={formState.errors.hasta}>
        <input id="cerrar-hasta" type="date" aria-required className={claseInput(formState.errors.hasta)} {...register("hasta")} />
      </Campo>
    </FormModal>
  );
}
