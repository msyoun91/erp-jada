import { notFound } from "next/navigation";
import {
  puedeEditarEmpresa,
  puedeVerEmpresas,
  puedeTransferirMisEmpresas,
  puedeVerTodasLasEmpresas,
  puedeVincular,
  puedeVincularPersonaEmpresa,
} from "@/modules/obras/permissions";
import {
  getFichaEmpresa,
  getRelacionesEmpresa,
  getUsuariosParaTransferir,
  getUsuarioActualId,
} from "@/modules/obras/queries";
import { puedeVerLista } from "@/modules/tareas/permissions";
import { getRegistro, getTareasContexto, getTareasDeRegistro } from "@/modules/tareas/queries";
import { EmpresaDetalle } from "@/modules/obras/components/EmpresaDetalle";
import { TareasDeRegistro } from "@/modules/tareas/components/TareasDeRegistro";
import type { EmpresaFicha, EstadoObra, RolEmpresa } from "@/modules/obras/types";

export default async function EmpresaPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ ctx?: string }>;
}) {
  if (!(await puedeVerEmpresas())) notFound();

  const { id } = await params;

  // `?ctx=obra:<id>`: enlace desde una ficha de obra donde el usuario tiene
  // grant contextual sobre esta empresa (sql/085). Sin eso el contacto solo lo
  // abre el dueño / grant directo / obras_empresas_todas.
  const { ctx: ctxParam } = await searchParams;
  const ctxObraId = ctxParam?.match(/^obra:([0-9a-f-]{36})$/)?.[1];

  const [
    ficha,
    relaciones,
    editar,
    vincularPersona,
    vincular,
    veTodas,
    transferirPropias,
    usuarios,
    miId,
    verTareas,
  ] = await Promise.all([
    getFichaEmpresa(id, ctxObraId).catch(() => null),
    getRelacionesEmpresa(id),
    puedeEditarEmpresa(),
    puedeVincularPersonaEmpresa(),
    puedeVincular(),
    puedeVerTodasLasEmpresas(),
    puedeTransferirMisEmpresas(),
    getUsuariosParaTransferir(),
    getUsuarioActualId(),
    puedeVerLista(),
  ]);
  if (!ficha || !relaciones) notFound();

  // El estado no entra en la firma de `obras_ficha_empresa`: viene del select
  // de relaciones, igual que `getEstadoPersona` al lado de `getFichaPersona`.
  const empresa: EmpresaFicha = {
    ...ficha,
    pendiente: relaciones.pendiente,
    motivo_rechazo: relaciones.motivo_rechazo,
  };

  const [tareasContexto, tareasDeRegistro, registro] = await Promise.all([
    verTareas ? getTareasContexto() : Promise.resolve(null),
    verTareas ? getTareasDeRegistro("empresa", id) : Promise.resolve({ tareas: [], delHilo: [], hilos: [] }),
    verTareas ? getRegistro("empresa", id) : Promise.resolve(null),
  ]);

  const { obras_persona_empresa, obras_obra_empresa } = relaciones;
  // `esMio` también acota editar y desactivar: la RLS de update exige ser el
  // dueño (sql/039), así que sin esto el receptor ve botones que no andan.
  const esMio = !!miId && empresa.creado_por === miId;
  // El panel de transferencia lo muestra arriba de todo. `usuarios` no me
  // incluye, así que lo mío se resuelve por `esMio` y no por la búsqueda.
  const duenio = esMio ? "vos" : (usuarios.find((u) => u.id === empresa.creado_por)?.nombre ?? null);
  // Colgar la empresa de una obra propia pide que sea mía o obras_empresas_todas.
  // Espeja la RLS de obras_obra_empresa_insert (sql/086).
  const vincularObra = vincular && (esMio || veTodas);

  return (
    <EmpresaDetalle
      empresa={empresa}
      personas={obras_persona_empresa.map((v) => ({
        id: v.id,
        persona_id: v.obras_personas?.id ?? "",
        nombre:
          `${v.obras_personas?.nombre ?? ""} ${v.obras_personas?.apellido ?? ""}`.trim() || "—",
        cargo: v.cargo,
        es_principal: v.es_principal,
      }))}
      obras={obras_obra_empresa
        .filter((v) => v.obras)
        .map((v) => ({
          id: v.id,
          obra_id: v.obras!.id,
          nombre: v.obras!.nombre,
          estado: v.obras!.estado as EstadoObra,
          localidad: v.obras!.localidad,
          roles: v.roles as RolEmpresa[],
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
      permisos={{ editar: editar && esMio, vincularPersona, vincularObra }}
      duenio={duenio}
      puedeTransferir={veTodas || (transferirPropias && esMio)}
      usuarios={usuarios.filter((u) => u.id !== miId)}
    />
  );
}
