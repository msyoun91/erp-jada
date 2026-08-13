import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { puedeAsignarTarea, puedeCrearTarea, puedeVerMisTareas } from "@/modules/tareas/permissions";
import {
  getHilosDisponibles,
  getMisTareasAbiertas,
  getMisTareasCompletadasCount,
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

  const [tareasAbiertas, totalCompletadas, hilos, usuarios, puedeCrear, puedeAsignar] = await Promise.all([
    getMisTareasAbiertas(),
    getMisTareasCompletadasCount(),
    getHilosDisponibles(),
    getUsuariosParaAsignar(),
    puedeCrearTarea(),
    puedeAsignarTarea(),
  ]);

  return (
    <TareasView
      tareasAbiertas={tareasAbiertas}
      totalCompletadas={totalCompletadas}
      hilos={hilos}
      usuarios={usuarios}
      usuarioActualId={user.id}
      puedeCrear={puedeCrear}
      puedeAsignar={puedeAsignar}
      modo="mis"
    />
  );
}
