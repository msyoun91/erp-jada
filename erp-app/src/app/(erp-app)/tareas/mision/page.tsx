import { notFound } from "next/navigation";
import { puedeAsignar, puedeGestionarAjenas, puedeVerMision } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getMiembrosPorProyecto,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
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
      <MisionView hilos={hilos} tareas={tareas} />
    </TareasContextoProvider>
  );
}
