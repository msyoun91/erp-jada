import { notFound } from "next/navigation";
import { puedeAsignar, puedeGestionarAjenas, puedeVerMision } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getMiembrosPorProyecto,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { MisionView } from "@/modules/tareas/components/MisionView";

export default async function MisionPage() {
  if (!(await puedeVerMision())) notFound();

  const [{ hilos, tareas }, usuarios, proyectos, miembrosPorProyecto, gestionarAjenas, asignar, usuarioActualId] =
    await Promise.all([
      getListaTareas(),
      getUsuariosParaAsignar(),
      getProyectos(),
      getMiembrosPorProyecto(),
      puedeGestionarAjenas(),
      puedeAsignar(),
      getUsuarioActualId(),
    ]);

  return (
    <MisionView
      hilos={hilos}
      tareas={tareas}
      usuarios={usuarios}
      proyectos={proyectos}
      miembrosPorProyecto={miembrosPorProyecto}
      gestionarAjenas={gestionarAjenas}
      puedeAsignar={asignar}
      usuarioActualId={usuarioActualId}
    />
  );
}
