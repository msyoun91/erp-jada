import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { puedeAsignarTarea, puedeCrearTarea, puedeVerMisTareas } from "@/modules/tareas/permissions";
import {
  getHilosDisponibles,
  getMisTareasAbiertas,
  getMisTareasCompletadasCount,
  getMisTareasPospuestasCount,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { TareasView } from "@/modules/tareas/components/TareasView";

export default async function MisTareasPage() {
  if (!(await puedeVerMisTareas())) notFound();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) notFound();

  const [abiertas, totalCompletadas, totalPospuestas, hilos, usuarios, puedeCrear, puedeAsignar] = await Promise.all([
    getMisTareasAbiertas(),
    getMisTareasCompletadasCount(),
    getMisTareasPospuestasCount(),
    getHilosDisponibles(),
    getUsuariosParaAsignar(),
    puedeCrearTarea(),
    puedeAsignarTarea(),
  ]);

  return (
    <TareasView
      tareasAbiertas={abiertas.tareas}
      totalAbiertas={abiertas.total}
      totalCompletadas={totalCompletadas}
      totalPospuestas={totalPospuestas}
      hilos={hilos}
      usuarios={usuarios}
      usuarioActualId={user.id}
      puedeCrear={puedeCrear}
      puedeAsignar={puedeAsignar}
      modo="mis"
    />
  );
}
