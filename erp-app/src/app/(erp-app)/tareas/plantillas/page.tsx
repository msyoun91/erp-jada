import { notFound } from "next/navigation";
import {
  puedeAsignar,
  puedeCrearProyecto,
  puedeGestionarAjenas,
  puedeGestionarPlantillasSistema,
  puedeVerPlantillas,
} from "@/modules/tareas/permissions";
import {
  getEntes,
  getMiembrosPorProyecto,
  getPlantillas,
  getProyectos,
  getUsuarioActualId,
  getUsuariosParaAsignar,
} from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";

// El editor de pasos usa el mismo picker de asignados que el resto del
// módulo, y "Usar" elige proyecto destino: por eso esta vista también monta
// el contexto.
export default async function TareasPlantillasPage() {
  if (!(await puedeVerPlantillas())) notFound();

  const [
    plantillas,
    entes,
    usuarios,
    proyectos,
    miembrosPorProyecto,
    usuarioActualId,
    gestionarAjenas,
    asignar,
    sistema,
    crearProyecto,
  ] = await Promise.all([
    getPlantillas(),
    getEntes(),
    getUsuariosParaAsignar(),
    getProyectos(),
    getMiembrosPorProyecto(),
    getUsuarioActualId(),
    puedeGestionarAjenas(),
    puedeAsignar(),
    puedeGestionarPlantillasSistema(),
    puedeCrearProyecto(),
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
      <PlantillasView
        plantillas={plantillas}
        entes={entes}
        puedeSistema={sistema}
        puedeCrearProyecto={crearProyecto}
      />
    </TareasContextoProvider>
  );
}
