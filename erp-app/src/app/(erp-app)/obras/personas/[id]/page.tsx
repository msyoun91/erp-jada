import { notFound } from "next/navigation";
import {
  puedeEditarPersona,
  puedeVerPersonas,
  puedeVincular,
  puedeVincularPersonaEmpresa,
} from "@/modules/obras/permissions";
import {
  getEstadoPersona,
  getFichaPersona,
  getReferenciasDePersona,
  getVinculosPersona,
} from "@/modules/obras/queries";
import { Breadcrumb } from "@/modules/obras/components/Breadcrumb";
import { EstadoPendiente } from "@/modules/obras/components/EstadoPendiente";
import { PersonaDetalle } from "@/modules/obras/components/PersonaDetalle";
import type { EstadoObra, RolPersona } from "@/modules/obras/types";

export default async function PersonaPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await puedeVerPersonas())) notFound();

  const { id } = await params;

  // getFichaPersona registra el acceso: es la única puerta a los datos de
  // contacto, y tira si la persona está fuera del alcance del usuario.
  const [persona, estado] = await Promise.all([
    getFichaPersona(id).catch(() => null),
    getEstadoPersona(id),
  ]);

  // Rechazada: la fila sigue existiendo pero desactivada, así que la ficha ya
  // no la sirve. Sin esta pantalla, el alta rechazada es un registro que
  // desaparece sin explicación.
  if (!persona) {
    if (!estado || estado.activo || !estado.motivo_rechazo) notFound();

    return (
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <Breadcrumb
            padre="Personas"
            href="/obras/personas"
            actual={`${estado.nombre} ${estado.apellido ?? ""}`.trim()}
          />
        </div>
        <EstadoPendiente
          pendiente={false}
          motivoRechazo={estado.motivo_rechazo}
          queEs="Esta persona"
          detalle=""
        />
      </div>
    );
  }

  const [{ empresas, obras }, referencias, editar, vincularEmpresa, vincularObra] =
    await Promise.all([
      getVinculosPersona(id),
      getReferenciasDePersona(id),
      puedeEditarPersona(),
      puedeVincularPersonaEmpresa(),
      puedeVincular(),
    ]);

  const comisionPorObra = new Map(referencias.map((r) => [r.obra_id, r.porcentaje_comision]));

  return (
    <PersonaDetalle
      persona={persona}
      estado={{
        pendiente: estado?.pendiente ?? false,
        motivo_rechazo: estado?.motivo_rechazo ?? null,
      }}
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
          pendiente: v.pendiente,
        }))}
      permisos={{ editar, vincularEmpresa, vincularObra }}
    />
  );
}
