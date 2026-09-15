import { notFound } from "next/navigation";
import { puedeCrearProyecto, puedeGestionarMiembros, puedeVerProyectos } from "@/modules/tareas/permissions";
import { getListaTareas, getPlantillas, getTareasContexto } from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { ProyectosView } from "@/modules/tareas/components/ProyectosView";

export default async function TareasProyectosPage() {
  if (!(await puedeVerProyectos())) notFound();

  const [{ hilos, tareas }, plantillas, puedeCrear, gestionarMiembros, contexto] = await Promise.all([
    getListaTareas(),
    getPlantillas(),
    puedeCrearProyecto(),
    puedeGestionarMiembros(),
    getTareasContexto(),
  ]);

  return (
    <TareasContextoProvider valor={contexto}>
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
