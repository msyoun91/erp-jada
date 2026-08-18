import { notFound } from "next/navigation";
import { puedeVerAuditoria } from "@/modules/tareas/permissions";
import { getAuditoria, getPendientesUsuario, getUsuariosParaAsignar } from "@/modules/tareas/queries";
import { AuditoriaView } from "@/modules/tareas/components/AuditoriaView";
import { hoyISO, sumarDiasISO } from "@/lib/utils";

export default async function TareasAuditoriaPage({
  searchParams,
}: {
  searchParams: Promise<{ desde?: string; hasta?: string; usuario?: string }>;
}) {
  if (!(await puedeVerAuditoria())) notFound();

  const params = await searchParams;
  const desde = params.desde ?? sumarDiasISO(hoyISO(), -30);
  const hasta = params.hasta ?? hoyISO();
  const usuarioId = params.usuario ?? "";

  const [eventos, usuarios, pendientes] = await Promise.all([
    getAuditoria(desde, hasta, usuarioId || undefined),
    getUsuariosParaAsignar(),
    usuarioId ? getPendientesUsuario(usuarioId) : Promise.resolve([]),
  ]);

  return (
    <AuditoriaView
      eventos={eventos}
      usuarios={usuarios}
      pendientes={pendientes}
      desde={desde}
      hasta={hasta}
      usuarioId={usuarioId}
    />
  );
}
