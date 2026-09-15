import { notFound } from "next/navigation";
import { puedeVerMision } from "@/modules/tareas/permissions";
import { getListaTareas, getTareasContexto } from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { MisionView } from "@/modules/tareas/components/MisionView";

export default async function MisionPage() {
  if (!(await puedeVerMision())) notFound();

  const [{ hilos, tareas }, contexto] = await Promise.all([getListaTareas(), getTareasContexto()]);

  return (
    <TareasContextoProvider valor={contexto}>
      <MisionView hilos={hilos} tareas={tareas} />
    </TareasContextoProvider>
  );
}
