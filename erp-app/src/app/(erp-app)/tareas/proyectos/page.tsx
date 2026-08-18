import { notFound } from "next/navigation";
import { puedeCrearProyecto, puedeGestionarAjenas, puedeVerProyectos } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getMiembrosPorProyecto,
  getPlantillas,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { ProyectosView } from "@/modules/tareas/components/ProyectosView";

export default async function TareasProyectosPage() {
  if (!(await puedeVerProyectos())) notFound();

  const [
    proyectos,
    { hilos, tareas },
    usuarios,
    plantillas,
    miembrosPorProyecto,
    puedeCrear,
    gestionarAjenas,
    usuarioActualId,
  ] = await Promise.all([
    getProyectos(),
    getListaTareas(),
    getUsuariosParaAsignar(),
    getPlantillas(),
    getMiembrosPorProyecto(),
    puedeCrearProyecto(),
    puedeGestionarAjenas(),
    getUsuarioActualId(),
  ]);

  return (
    <ProyectosView
      proyectos={proyectos}
      hilos={hilos}
      tareas={tareas}
      usuarios={usuarios}
      plantillas={plantillas}
      miembrosPorProyecto={miembrosPorProyecto}
      usuarioActualId={usuarioActualId}
      gestionarAjenas={gestionarAjenas}
      puedeCrear={puedeCrear}
    />
  );
}
