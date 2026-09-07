import { notFound } from "next/navigation";
import {
  puedeEditarPersona,
  puedeVerPersonas,
  puedeVincularPersonaEmpresa,
} from "@/modules/obras/permissions";
import {
  getEmpresas,
  getFichaPersona,
  getReferenciasDePersona,
  getVinculosPersona,
} from "@/modules/obras/queries";
import { PersonaDetalle } from "@/modules/obras/components/PersonaDetalle";
import type { EstadoObra, RolPersona } from "@/modules/obras/types";

export default async function PersonaPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await puedeVerPersonas())) notFound();

  const { id } = await params;

  // getFichaPersona registra el acceso: es la única puerta a los datos de
  // contacto, y tira si la persona está fuera del alcance del usuario.
  const persona = await getFichaPersona(id).catch(() => null);
  if (!persona) notFound();

  const [{ empresas, obras }, referencias, editar, vincularEmpresa] = await Promise.all([
    getVinculosPersona(id),
    getReferenciasDePersona(id),
    puedeEditarPersona(),
    puedeVincularPersonaEmpresa(),
  ]);

  const empresasDisponibles = vincularEmpresa
    ? (await getEmpresas()).map((e) => ({ id: e.id, razon_social: e.razon_social }))
    : [];

  const comisionPorObra = new Map(referencias.map((r) => [r.obra_id, r.porcentaje_comision]));

  return (
    <PersonaDetalle
      persona={persona}
      empresas={empresas
        .filter((v) => v.obras_empresas)
        .map((v) => ({
          id: v.id,
          empresa_id: v.obras_empresas!.id,
          razon_social: v.obras_empresas!.razon_social,
          cargo: v.cargo,
          es_principal: v.es_principal,
        }))}
      obras={obras
        .filter((v) => v.obras)
        .map((v) => ({
          id: v.id,
          obra_id: v.obras!.id,
          nombre: v.obras!.nombre,
          estado: v.obras!.estado as EstadoObra,
          empresa: v.obras_empresas?.razon_social ?? null,
          roles: v.roles as RolPersona[],
          comision: comisionPorObra.get(v.obras!.id) ?? null,
        }))}
      empresasDisponibles={empresasDisponibles}
      permisos={{ editar, vincularEmpresa }}
    />
  );
}
