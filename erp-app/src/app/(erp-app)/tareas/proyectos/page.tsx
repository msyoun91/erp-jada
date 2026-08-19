import { notFound } from "next/navigation";
import {
  puedeCrearProyecto,
  puedeGestionarAjenas,
  puedeGestionarMiembros,
  puedeVerProyectos,
} from "@/modules/tareas/permissions";
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
    gestionarMiembros,
    usuarioActualId,
  ] = await Promise.all([
    getProyectos(),
    getListaTareas(),
    getUsuariosParaAsignar(),
    getPlantillas(),
    getMiembrosPorProyecto(),
    puedeCrearProyecto(),
    puedeGestionarAjenas(),
    puedeGestionarMiembros(),
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
      gestionarMiembros={gestionarMiembros}
      puedeCrear={puedeCrear}
    />
  );
}
