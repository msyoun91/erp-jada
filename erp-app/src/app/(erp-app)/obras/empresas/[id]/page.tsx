import { notFound } from "next/navigation";
import {
  puedeEditarEmpresa,
  puedeVerEmpresas,
  puedeVerTodasLasEmpresas,
  puedeVincular,
  puedeVincularPersonaEmpresa,
} from "@/modules/obras/permissions";
import {
  getCompartidosEmpresa,
  getEmpresa,
  getUsuariosParaTransferir,
  getUsuarioActualId,
  tieneGrantDirectoEmpresa,
} from "@/modules/obras/queries";
import { EmpresaDetalle } from "@/modules/obras/components/EmpresaDetalle";
import type { Empresa, EstadoObra, RolEmpresa } from "@/modules/obras/types";

export default async function EmpresaPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await puedeVerEmpresas())) notFound();

  const { id } = await params;
  const [
    empresa,
    editar,
    vincularPersona,
    vincular,
    veTodas,
    compartidos,
    usuarios,
    miId,
    grantDirecto,
  ] = await Promise.all([
    getEmpresa(id),
    puedeEditarEmpresa(),
    puedeVincularPersonaEmpresa(),
    puedeVincular(),
    puedeVerTodasLasEmpresas(),
    getCompartidosEmpresa(id),
    getUsuariosParaTransferir(),
    getUsuarioActualId(),
    tieneGrantDirectoEmpresa(id),
  ]);
  if (!empresa) notFound();

  const { obras_persona_empresa, obras_obra_empresa, ...datos } = empresa;
  const esMio = !!miId && empresa.creado_por === miId;
  // Colgar la empresa de una obra propia pide que sea mía: dueño, grant directo
  // o obras_empresas_todas. Espeja la RLS de obras_obra_empresa_insert (sql/052).
  const vincularObra = vincular && (esMio || grantDirecto || veTodas);

  return (
    <EmpresaDetalle
      empresa={datos as Empresa}
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
      permisos={{ editar, vincularPersona, vincularObra }}
      esMio={esMio}
      veTodas={veTodas}
      compartidos={compartidos}
      usuarios={usuarios.filter((u) => u.id !== miId)}
    />
  );
}
