import { notFound } from "next/navigation";
import {
  puedeCrearEmpresa,
  puedeCrearPersona,
  puedeDesactivarObra,
  puedeEditarObra,
  puedeTransferir,
  puedeVerObras,
  puedeVerReferentes,
  puedeVincular,
} from "@/modules/obras/permissions";
import {
  getEmpresas,
  getObra,
  getReferentes,
  getTransferencias,
  getUsuariosParaTransferir,
} from "@/modules/obras/queries";
import { ObraDetalle } from "@/modules/obras/components/ObraDetalle";
import type { Obra, RolEmpresa, RolPersona, Usuario } from "@/modules/obras/types";

export default async function ObraPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await puedeVerObras())) notFound();

  const { id } = await params;
  const obra = await getObra(id);
  if (!obra) notFound();

  const [editar, vincular, referentesPerm, transferir, desactivar, crearEmpresa, crearPersona] =
    await Promise.all([
      puedeEditarObra(),
      puedeVincular(),
      puedeVerReferentes(),
      puedeTransferir(),
      puedeDesactivarObra(),
      puedeCrearEmpresa(),
      puedeCrearPersona(),
    ]);

  // Solo se piden si hacen falta: la lista de empresas alimenta el panel de
  // vinculación y la de usuarios el de transferencia.
  const [empresasDisponibles, usuarios, referentes, transferencias] = await Promise.all([
    vincular ? getEmpresas() : Promise.resolve([]),
    transferir ? getUsuariosParaTransferir() : Promise.resolve([]),
    referentesPerm ? getReferentes(id) : Promise.resolve([]),
    getTransferencias(id),
  ]);

  const { obras_obra_empresa, obras_obra_persona, responsable, ...datos } = obra;

  const empresas = obras_obra_empresa.map((v) => ({
    id: v.id,
    empresa_id: v.obras_empresas?.id ?? "",
    roles: v.roles as RolEmpresa[],
    observaciones: v.observaciones,
    razon_social: v.obras_empresas?.razon_social ?? "—",
  }));

  const personas = obras_obra_persona.map((v) => ({
    id: v.id,
    persona_id: v.obras_personas?.id ?? "",
    empresa_id: v.empresa_id,
    roles: v.roles as RolPersona[],
    observaciones: v.observaciones,
    nombre: `${v.obras_personas?.nombre ?? ""} ${v.obras_personas?.apellido ?? ""}`.trim() || "—",
    empresa: v.obras_empresas?.razon_social ?? null,
  }));

  return (
    <ObraDetalle
      obra={datos as Obra}
      responsable={responsable as Usuario | null}
      empresas={empresas}
      personas={personas}
      referentes={referentes.map((r) => ({
        id: r.id,
        persona_id: r.persona_id,
        porcentaje_comision: r.porcentaje_comision,
        observaciones: r.observaciones,
        nombre:
          `${r.obras_personas?.nombre ?? ""} ${r.obras_personas?.apellido ?? ""}`.trim() || "—",
      }))}
      transferencias={transferencias.map((t) => ({
        id: t.id,
        created_at: t.created_at,
        de: t.de?.nombre ?? "—",
        a: t.a?.nombre ?? "—",
      }))}
      empresasDisponibles={empresasDisponibles}
      usuarios={usuarios}
      permisos={{
        editar,
        vincular,
        referentes: referentesPerm,
        transferir,
        desactivar,
        crearEmpresa,
        crearPersona,
      }}
    />
  );
}
