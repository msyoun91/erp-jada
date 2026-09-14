import { notFound } from "next/navigation";
import { puedeAsignar, puedeGestionarAjenas, puedeVerLista } from "@/modules/tareas/permissions";
import {
  getListaTareas,
  getMiembrosPorProyecto,
  getPlantillas,
  getProyectos,
  getRegistro,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { uuidSchema } from "@/modules/tareas/types";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { TareasListaView } from "@/modules/tareas/components/TareasListaView";

export default async function TareasPage({
  searchParams,
}: {
  searchParams: Promise<{ [clave: string]: string | string[] | undefined }>;
}) {
  if (!(await puedeVerLista())) notFound();

  // "Nueva tarea" desde la ficha de un registro de otro módulo: `?nueva=obra:{id}`.
  const { nueva } = await searchParams;
  const [ente, registroId] = typeof nueva === "string" ? nueva.split(":") : [];
  const pideNueva = Boolean(ente) && uuidSchema.safeParse(registroId).success;

  const [
    { hilos, tareas },
    usuarios,
    proyectos,
    plantillas,
    miembrosPorProyecto,
    gestionarAjenas,
    asignar,
    usuarioActualId,
    nuevaDesde,
  ] = await Promise.all([
    getListaTareas(),
    getUsuariosParaAsignar(),
    getProyectos(),
    getPlantillas(),
    getMiembrosPorProyecto(),
    puedeGestionarAjenas(),
    puedeAsignar(),
    getUsuarioActualId(),
    pideNueva ? getRegistro(ente, registroId) : Promise.resolve(null),
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
      <TareasListaView hilos={hilos} tareas={tareas} plantillas={plantillas} nuevaDesde={nuevaDesde} />
    </TareasContextoProvider>
  );
}
