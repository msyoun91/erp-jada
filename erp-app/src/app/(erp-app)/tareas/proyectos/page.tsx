import { notFound } from "next/navigation";
import {
  puedeAsignar,
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
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
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
    asignar,
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
    puedeAsignar(),
    getUsuarioActualId(),
  ]);

  return (
    <TareasContextoProvider
      valor={{
        usuarios,
        proyectos,
        miembrosPorProyecto,
        usuarioActualId,
        gestionarAjenas,
        puedeAsignar: asignar,
      }}
    >
      <ProyectosView
        hilos={hilos}
        tareas={tareas}
        plantillas={plantillas}
        gestionarMiembros={gestionarMiembros}
        puedeCrear={puedeCrear}
      />
    </TareasContextoProvider>
  );
}
