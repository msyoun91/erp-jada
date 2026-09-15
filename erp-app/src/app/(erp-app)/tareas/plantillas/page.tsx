import { notFound } from "next/navigation";
import {
  puedeCrearProyecto,
  puedeGestionarPlantillasSistema,
  puedeVerPlantillas,
} from "@/modules/tareas/permissions";
import { getEntes, getPlantillas, getTareasContexto } from "@/modules/tareas/queries";
import { TareasContextoProvider } from "@/modules/tareas/components/tareasContexto";
import { PlantillasView } from "@/modules/tareas/components/PlantillasView";

// El editor de pasos usa el mismo picker de asignados que el resto del
// módulo, y "Usar" elige proyecto destino: por eso esta vista también monta
// el contexto.
export default async function TareasPlantillasPage() {
  if (!(await puedeVerPlantillas())) notFound();

  const [plantillas, entes, sistema, crearProyecto, contexto] = await Promise.all([
    getPlantillas(),
    getEntes(),
    puedeGestionarPlantillasSistema(),
    puedeCrearProyecto(),
    getTareasContexto(),
  ]);

  return (
    <TareasContextoProvider valor={contexto}>
      <PlantillasView
        plantillas={plantillas}
        entes={entes}
        puedeSistema={sistema}
        puedeCrearProyecto={crearProyecto}
      />
    </TareasContextoProvider>
  );
}
