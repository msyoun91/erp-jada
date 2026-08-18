import { notFound } from "next/navigation";
import { puedeCrearProyecto, puedeGestionarAjenas, puedeVerProyectos } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getPlantillas,
  getProyectoMiembros,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { ProyectosView } from "@/modules/tareas/components/ProyectosView";
import type { ProyectoMiembro } from "@/modules/tareas/types";

export default async function TareasProyectosPage() {
  if (!(await puedeVerProyectos())) notFound();

  const [proyectos, { hilos, tareas }, usuarios, plantillas, puedeCrear, gestionarAjenas, usuarioActualId] =
    await Promise.all([
      getProyectos(),
      getListaTareas(),
      getUsuariosParaAsignar(),
      getPlantillas(),
      puedeCrearProyecto(),
      puedeGestionarAjenas(),
      getUsuarioActualId(),
    ]);

  const privados = proyectos.filter((p) => p.visibilidad === "privado");
  const miembrosPorProyecto: Record<string, ProyectoMiembro[]> = {};
  await Promise.all(
    privados.map(async (p) => {
      miembrosPorProyecto[p.id] = await getProyectoMiembros(p.id);
    })
  );

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
