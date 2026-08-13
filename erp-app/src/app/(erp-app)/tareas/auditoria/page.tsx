import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { hoyISO, sumarDias } from "@/lib/utils";
import { puedeVerAuditoria } from "@/modules/tareas/permissions";
import { getAuditoria, getUsuariosParaAsignar } from "@/modules/tareas/queries";
import { AuditoriaView } from "@/modules/tareas/components/AuditoriaView";

export default async function AuditoriaPage() {
  if (!(await puedeVerAuditoria())) notFound();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) notFound();

  const hasta = hoyISO();
  const desde = sumarDias(hasta, -6);

  const [auditoria, usuarios] = await Promise.all([getAuditoria({ desde, hasta }), getUsuariosParaAsignar()]);

  return (
    <AuditoriaView
      diasIniciales={auditoria.dias}
      totalInicial={auditoria.total}
      filtrosIniciales={{ desde, hasta }}
      usuarios={usuarios}
      usuarioActualId={user.id}
    />
  );
}
