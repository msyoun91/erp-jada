import { notFound } from "next/navigation";
import {
  puedeEditarEmpresa,
  puedeVerEmpresas,
  puedeVincular,
  puedeVincularPersonaEmpresa,
} from "@/modules/obras/permissions";
import { getEmpresa } from "@/modules/obras/queries";
import { EmpresaDetalle } from "@/modules/obras/components/EmpresaDetalle";
import type { Empresa, EstadoObra, RolEmpresa } from "@/modules/obras/types";

export default async function EmpresaPage({ params }: { params: Promise<{ id: string }> }) {
  if (!(await puedeVerEmpresas())) notFound();

  const { id } = await params;
  const [empresa, editar, vincularPersona, vincularObra] = await Promise.all([
    getEmpresa(id),
    puedeEditarEmpresa(),
    puedeVincularPersonaEmpresa(),
    puedeVincular(),
  ]);
  if (!empresa) notFound();

  const { obras_persona_empresa, obras_obra_empresa, ...datos } = empresa;

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
          pendiente: v.pendiente,
        }))}
      permisos={{ editar, vincularPersona, vincularObra }}
    />
  );
}
