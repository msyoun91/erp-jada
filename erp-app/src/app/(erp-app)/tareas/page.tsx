import { notFound } from "next/navigation";
import { puedeGestionarAjenas, puedeVerLista } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getPlantillas,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { TareasListaView } from "@/modules/tareas/components/TareasListaView";

export default async function TareasPage() {
  if (!(await puedeVerLista())) notFound();

  const [{ hilos, tareas }, usuarios, proyectos, plantillas, gestionarAjenas, usuarioActualId] = await Promise.all([
    getListaTareas(),
    getUsuariosParaAsignar(),
    getProyectos(),
    getPlantillas(),
    puedeGestionarAjenas(),
    getUsuarioActualId(),
  ]);

  return (
    <TareasListaView
      hilos={hilos}
      tareas={tareas}
      usuarios={usuarios}
      proyectos={proyectos}
      plantillas={plantillas}
      gestionarAjenas={gestionarAjenas}
      usuarioActualId={usuarioActualId}
    />
  );
}
