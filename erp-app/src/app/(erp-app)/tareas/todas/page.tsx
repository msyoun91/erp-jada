import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { puedeAsignarTarea, puedeCrearTarea, puedeVerTodasLasTareas } from "@/modules/tareas/permissions";
import {
  getHilosDisponibles,
  getTodasLasTareasAbiertas,
  getTodasLasTareasCompletadasCount,
  getTodasLasTareasPospuestasCount,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { TareasView } from "@/modules/tareas/components/TareasView";

export default async function TodasLasTareasPage() {
  if (!(await puedeVerTodasLasTareas())) notFound();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) notFound();

  const [abiertas, totalCompletadas, totalPospuestas, hilos, usuarios, puedeCrear, puedeAsignar] = await Promise.all([
    getTodasLasTareasAbiertas(),
    getTodasLasTareasCompletadasCount(),
    getTodasLasTareasPospuestasCount(),
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
      modo="todas"
    />
  );
}
