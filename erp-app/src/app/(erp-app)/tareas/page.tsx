import { notFound } from "next/navigation";
import { puedeVerLista } from "@/modules/tareas/permissions";
import { getListaTareas, getPlantillas, getTareasContexto } from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { TareasListaView } from "@/modules/tareas/components/TareasListaView";

export default async function TareasPage() {
  if (!(await puedeVerLista())) notFound();

  const [{ hilos, tareas }, plantillas, contexto] = await Promise.all([
    getListaTareas(),
    getPlantillas(),
    getTareasContexto(),
  ]);

  return (
    <TareasContextoProvider valor={contexto}>
      <TareasListaView hilos={hilos} tareas={tareas} plantillas={plantillas} />
    </TareasContextoProvider>
  );
}
