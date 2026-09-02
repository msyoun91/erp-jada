import { notFound } from "next/navigation";
import { puedeAsignar, puedeGestionarAjenas, puedeVerLista } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getMiembrosPorProyecto,
  getPlantillas,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { TareasListaView } from "@/modules/tareas/components/TareasListaView";

export default async function TareasPage() {
  if (!(await puedeVerLista())) notFound();

  const [
    { hilos, tareas },
    usuarios,
    proyectos,
    plantillas,
    miembrosPorProyecto,
    gestionarAjenas,
    asignar,
    usuarioActualId,
  ] = await Promise.all([
    getListaTareas(),
    getUsuariosParaAsignar(),
    getProyectos(),
    getPlantillas(),
    getMiembrosPorProyecto(),
    puedeGestionarAjenas(),
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
      <TareasListaView hilos={hilos} tareas={tareas} plantillas={plantillas} />
    </TareasContextoProvider>
  );
}
