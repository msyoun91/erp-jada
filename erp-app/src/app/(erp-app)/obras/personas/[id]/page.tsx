import { notFound } from "next/navigation";
import {
  puedeEditarPersona,
  puedeVerPersonas,
  puedeTransferirMisPersonas,
  puedeVerTodasLasPersonas,
  puedeVincular,
  puedeVincularPersonaEmpresa,
} from "@/modules/obras/permissions";
import {
  getEstadoPersona,
  getFichaPersona,
  getReferenciasDePersona,
  getUsuariosParaTransferir,
  getUsuarioActualId,
  getVinculosPersona,
} from "@/modules/obras/queries";
import { puedeVerLista } from "@/modules/tareas/permissions";
import { getRegistro, getTareasContexto, getTareasDeRegistro } from "@/modules/tareas/queries";
import { Breadcrumb } from "@/modules/obras/components/Breadcrumb";
import { EstadoPendiente } from "@/modules/obras/components/EstadoPendiente";
import { PersonaDetalle } from "@/modules/obras/components/PersonaDetalle";
import { TareasDeRegistro } from "@/modules/tareas/components/TareasDeRegistro";
import type { EstadoObra, RolPersona } from "@/modules/obras/types";

export default async function PersonaPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ctx?: string }>;
}) {
  if (!(await puedeVerPersonas())) notFound();

  const { id } = await params;

  // `?ctx=obra:<id>` / `empresa:<id>`: enlace desde una ficha donde el usuario
  // tiene grant contextual. Sin eso el contacto solo lo abre el dueño / grant
  // completo / obras_personas_todas.
  const { ctx: ctxParam } = await searchParams;
  const m = ctxParam?.match(/^(obra|empresa):([0-9a-f-]{36})$/);
  const ctx = m ? { tipo: m[1] as "obra" | "empresa", id: m[2] } : undefined;

  // getFichaPersona registra el acceso: es la única puerta a los datos de
  // contacto, y tira si la persona está fuera del alcance del usuario.
  const [persona, estado] = await Promise.all([
    getFichaPersona(id, ctx).catch(() => null),
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

  const [
    { empresas, obras },
    referencias,
    editar,
    vincularEmpresa,
    vincular,
    veTodas,
    transferirPropias,
    usuarios,
    miId,
    verTareas,
  ] = await Promise.all([
    getVinculosPersona(id),
    getReferenciasDePersona(id),
    puedeEditarPersona(),
    puedeVincularPersonaEmpresa(),
    puedeVincular(),
    puedeVerTodasLasPersonas(),
    puedeTransferirMisPersonas(),
    getUsuariosParaTransferir(),
    getUsuarioActualId(),
    puedeVerLista(),
  ]);

  const [tareasContexto, tareasDeRegistro, registro] = await Promise.all([
    verTareas ? getTareasContexto() : Promise.resolve(null),
    verTareas ? getTareasDeRegistro("persona", id) : Promise.resolve({ tareas: [], delHilo: [], hilos: [] }),
    verTareas ? getRegistro("persona", id) : Promise.resolve(null),
  ]);

  const comisionPorObra = new Map(referencias.map((r) => [r.obra_id, r.porcentaje_comision]));
  // `esMio` también acota editar y desactivar: la RLS de update exige ser el
  // dueño (sql/039), así que sin esto el receptor ve botones que no andan.
  const esMio = !!miId && persona.creado_por === miId;
  // Colgar la persona de una obra propia pide que sea mía o obras_personas_todas.
  // Espeja la RLS de obras_obra_persona_insert (sql/086).
  const vincularObra = vincular && (esMio || veTodas);

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
        }))}
      seccionTareas={
        verTareas && tareasContexto && registro ? (
          <TareasDeRegistro
            contexto={tareasContexto}
            registro={registro}
            tareas={tareasDeRegistro.tareas}
            delHilo={tareasDeRegistro.delHilo}
            hilos={tareasDeRegistro.hilos}
          />
        ) : null
      }
      permisos={{ editar: editar && esMio, vincularEmpresa, vincularObra }}
      esMio={esMio}
      puedeTransferir={veTodas || (transferirPropias && esMio)}
      usuarios={usuarios.filter((u) => u.id !== miId)}
    />
  );
}
