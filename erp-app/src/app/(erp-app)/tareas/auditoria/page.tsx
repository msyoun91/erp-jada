import { notFound } from "next/navigation";
import { z } from "zod";
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

  // Un parámetro inválido en la URL rompía la vista entera (Postgres rechaza la
  // fecha o el uuid): se ignora y vale el default.
  const params = await searchParams;
  const fecha = (v: string | undefined) => (z.iso.date().safeParse(v).success ? v : undefined);
  const desde = fecha(params.desde) ?? sumarDiasISO(hoyISO(), -30);
  const hasta = fecha(params.hasta) ?? hoyISO();
  const usuarioId = params.usuario && z.uuid().safeParse(params.usuario).success ? params.usuario : "";

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
